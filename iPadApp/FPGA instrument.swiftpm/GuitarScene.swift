import Foundation
import SpriteKit
import UIKit

final class GuitarScene: SKScene {
    private unowned let session: GuitarPracticeSession
    private let chart: GuitarChart
    private let audio: GuitarSoundEngine

    private let boardLayer = SKNode()
    private let stringLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let overlayLayer = SKNode()

    private var noteNodes: [Int: SKNode] = [:]
    private var stringMoveNodes: [SKNode] = []
    private var stringPressNodes: [SKShapeNode] = []
    private var laneGlowNodes: [SKShapeNode] = []
    private var targetNodes: [SKShapeNode] = []
    private var stringYs: [CGFloat] = []
    private var stringHitRects: [CGRect] = []
    private var pressedCounts: [Int] = Array(repeating: 0, count: GuitarString.allCases.count)
    private var activeTouches: [ObjectIdentifier: Int] = [:]

    private var headX: CGFloat = 0
    private var bridgeX: CGFloat = 0
    private var bodyEndX: CGFloat = 0
    private var stringSpacing: CGFloat = 1
    private var stringCenterY: CGFloat = 0

    private var countdownLabel: SKLabelNode?
    private var countdownHint: SKLabelNode?
    private var lastRunID = -1
    private var lastPhase: PracticePhase = .idle
    private var didSetup = false
    private var layoutIsValid = false

    init(session: GuitarPracticeSession, chart: GuitarChart, audio: GuitarSoundEngine) {
        self.session = session
        self.chart = chart
        self.audio = audio
        super.init(size: CGSize(width: 1100, height: 620))
        anchorPoint = .zero
        scaleMode = .resizeFill
        backgroundColor = PixelPalette.backgroundUI
        isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.isMultipleTouchEnabled = true
        isPaused = false

        guard !didSetup else {
            rebuildLayout()
            return
        }

        didSetup = true
        boardLayer.zPosition = 0
        stringLayer.zPosition = 10
        noteLayer.zPosition = 20
        effectLayer.zPosition = 30
        overlayLayer.zPosition = 100

        addChild(boardLayer)
        addChild(stringLayer)
        addChild(noteLayer)
        addChild(effectLayer)
        addChild(overlayLayer)

        createCountdownLabels()
        rebuildLayout()
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        clearInputState()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard didSetup else { return }
        rebuildLayout()
    }

    override func update(_ currentTime: TimeInterval) {
        guard layoutIsValid else {
            session.pause()
            return
        }

        session.advance(to: currentTime)

        if session.runID != lastRunID {
            lastRunID = session.runID
            resetVisualState()
            lastPhase = session.phase
        } else if session.phase != lastPhase {
            handlePhaseChange(to: session.phase)
            lastPhase = session.phase
        }

        for event in session.drainEvents() {
            present(event, now: currentTime)
        }

        syncNoteNodes()
        updateCountdown()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let canPlaySound: Bool = session.phase == .playing || session.phase == .countdown
        var lanes: [Int] = []
        var seenLanes = Set<Int>()
        var latestTimestamp: TimeInterval = 0

        for touch in touches {
            let point = touch.location(in: self)
            guard let lane = laneIndex(at: point) else { continue }
            let touchKey = ObjectIdentifier(touch)
            if activeTouches[touchKey] == nil {
                activeTouches[touchKey] = lane
                if pressedCounts.indices.contains(lane) {
                    pressedCounts[lane] += 1
                }
            }
            if seenLanes.insert(lane).inserted {
                lanes.append(lane)
                if canPlaySound {
                    session.performanceController?.guitarPluck(
                        stringIndex: lane,
                        selectedFret: session.selectedFret,
                        selectedChordID: session.selectedChordID,
                        velocity: 15,
                        local: { playLocalString(lane: lane) }
                    )
                }
                vibrateString(lane: lane, amplitude: 2.5)
            }
            latestTimestamp = max(latestTimestamp, touch.timestamp)
        }

        guard !lanes.isEmpty else { return }
        updatePressState()

        guard session.phase == .playing else { return }
        session.alignInput(to: latestTimestamp)
        guard session.phase == .playing else {
            clearInputState()
            return
        }

        let hitTime: TimeInterval = session.practiceTime
        for lane in lanes {
            if let target = session.upcomingTarget(
                at: hitTime,
                within: chart.practiceChart.goodWindow,
                lane: lane
            ) {
                if session.isLeftMatched(for: target) {
                    session.registerHit(lane: lane, at: hitTime)
                } else {
                    session.registerForcedMiss(noteID: target.id, lane: lane)
                    session.setLeftFeedback(
                        "左手未匹配：目标 \(target.left.displayText) · 当前 \(session.selectedLeft.displayText)"
                    )
                }
            } else {
                session.registerHit(lane: lane, at: hitTime)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    private func playLocalString(lane: Int) {
        guard GuitarString.displayOrder.indices.contains(lane) else { return }
        let string: GuitarString = GuitarString.displayOrder[lane]
        if let chordID = session.selectedChordID,
           let chord = FPGAKeyMap.guitarChords.first(where: { $0.id == chordID }) {
            for tone in chord.tones {
                audio.play(midiNote: tone.midiNote, velocity: 15)
            }
            return
        }
        audio.play(
            midiNote: string.openMidi + session.selectedFret,
            velocity: 15
        )
    }

    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            let touchKey = ObjectIdentifier(touch)
            guard let lane = activeTouches.removeValue(forKey: touchKey) else { continue }
            if pressedCounts.indices.contains(lane) {
                pressedCounts[lane] = max(0, pressedCounts[lane] - 1)
            }
        }
        updatePressState()
    }

    private func clearInputState() {
        activeTouches.removeAll(keepingCapacity: true)
        for index in pressedCounts.indices {
            pressedCounts[index] = 0
        }
        updatePressState()
    }

    private func updatePressState() {
        guard stringPressNodes.count == pressedCounts.count else { return }
        for index in stringPressNodes.indices {
            let pressed: Bool = pressedCounts[index] > 0
            stringPressNodes[index].alpha = pressed ? 0.55 : 0
        }
    }

    private func vibrateString(lane: Int, amplitude: CGFloat) {
        guard stringMoveNodes.indices.contains(lane) else { return }
        let node = stringMoveNodes[lane]
        node.removeAllActions()
        node.position = .zero
        let down = SKAction.moveBy(x: 0, y: -amplitude, duration: 0.035)
        let up = SKAction.moveBy(x: 0, y: amplitude * 2.0, duration: 0.055)
        let settle = SKAction.moveBy(x: 0, y: -amplitude, duration: 0.045)
        node.run(SKAction.sequence([down, up, settle]))
    }

    private func handlePhaseChange(to newPhase: PracticePhase) {
        if newPhase == .paused || newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            session.releasePerformancePage()
        }
        if newPhase == .paused {
            stringLayer.speed = 0
            noteLayer.speed = 0
            effectLayer.speed = 0
            audio.stopAll()
            clearInputState()
            return
        }

        stringLayer.speed = 1
        noteLayer.speed = 1
        effectLayer.speed = 1

        if newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            clearInputState()
        }
    }

    private func resetVisualState() {
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()
        stringLayer.speed = 1
        noteLayer.speed = 1
        effectLayer.speed = 1
        audio.stopAll()
        for node in stringMoveNodes {
            node.removeAllActions()
            node.position = .zero
        }
        clearInputState()
    }

    private func rebuildLayout() {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 260, height > 220 else {
            layoutIsValid = false
            stringYs.removeAll(keepingCapacity: true)
            stringHitRects.removeAll(keepingCapacity: true)
            noteLayer.removeAllChildren()
            noteNodes.removeAll(keepingCapacity: true)
            clearInputState()
            return
        }

        let sideInset: CGFloat = min(max(width * 0.018, 8), 22)
        let spacing: CGFloat = min(max(height * 0.083, 30), 52)
        stringSpacing = spacing
        let centerY: CGFloat = height * 0.54
        stringCenterY = centerY
        headX = width * 0.17
        bridgeX = width * 0.80
        bodyEndX = width * 0.94

        stringYs.removeAll(keepingCapacity: true)
        stringHitRects.removeAll(keepingCapacity: true)
        for index in 0..<6 {
            let offset: CGFloat = (2.5 - CGFloat(index)) * spacing
            let y: CGFloat = centerY + offset
            stringYs.append(y)
            let hitRect = CGRect(
                x: 0,
                y: y - spacing * 0.47,
                width: width,
                height: spacing * 0.94
            )
            stringHitRects.append(hitRect)
        }

        boardLayer.removeAllChildren()
        stringLayer.removeAllChildren()
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()
        stringMoveNodes.removeAll(keepingCapacity: true)
        stringPressNodes.removeAll(keepingCapacity: true)
        laneGlowNodes.removeAll(keepingCapacity: true)
        targetNodes.removeAll(keepingCapacity: true)

        buildGuitar(width: width, height: height, sideInset: sideInset)
        buildStrings(width: width)
        buildStringLabels(sideInset: sideInset)
        buildBridge(width: width)
        buildCountdownPositions(width: width, height: height)

        syncNoteNodes()
        updatePressState()
        layoutIsValid = true
    }

    private func buildGuitar(width: CGFloat, height: CGFloat, sideInset: CGFloat) {
        let bodyCenterX: CGFloat = width * 0.77
        let bodyWidth: CGFloat = width * 0.36
        let bodyHeight: CGFloat = height * 0.64
        let neckY: CGFloat = stringCenterY
        let neckHeight: CGFloat = stringSpacing * 6.2
        let neckStart: CGFloat = width * 0.10
        let neckEnd: CGFloat = width * 0.70

        let shadowOffset: CGFloat = 4
        let lowerShadow = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth, height: bodyHeight * 0.68)
        )
        lowerShadow.fillColor = PixelPalette.shadowUI
        lowerShadow.strokeColor = .clear
        lowerShadow.position = CGPoint(
            x: bodyCenterX,
            y: stringCenterY - shadowOffset
        )
        lowerShadow.zPosition = 1
        boardLayer.addChild(lowerShadow)

        let upperShadow = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth * 0.62, height: bodyHeight * 0.46)
        )
        upperShadow.fillColor = PixelPalette.shadowUI
        upperShadow.strokeColor = .clear
        upperShadow.position = CGPoint(
            x: bodyCenterX - bodyWidth * 0.18,
            y: stringCenterY - shadowOffset
        )
        upperShadow.zPosition = 1
        boardLayer.addChild(upperShadow)

        let neck = SKShapeNode(
            rect: CGRect(
                x: neckStart,
                y: neckY - neckHeight / 2,
                width: neckEnd - neckStart,
                height: neckHeight
            ),
            cornerRadius: 4
        )
        neck.fillColor = PixelPalette.accentDarkUI
        neck.strokeColor = PixelPalette.inkUI
        neck.lineWidth = 1.5
        neck.zPosition = 2
        boardLayer.addChild(neck)

        let headstock = SKShapeNode(
            rect: CGRect(
                x: width * 0.055,
                y: neckY - neckHeight * 0.42,
                width: width * 0.10,
                height: neckHeight * 0.84
            ),
            cornerRadius: 4
        )
        headstock.fillColor = PixelPalette.accentDarkUI
        headstock.strokeColor = PixelPalette.inkUI
        headstock.lineWidth = 1.5
        headstock.zPosition = 2
        boardLayer.addChild(headstock)

        let pegSize: CGFloat = max(4, min(8, width * 0.007))
        for index in 0..<6 {
            let pegY: CGFloat = neckY + (2.5 - CGFloat(index)) * neckHeight * 0.12
            let leftPeg = SKShapeNode(
                rectOf: CGSize(width: pegSize, height: pegSize),
                cornerRadius: 0
            )
            leftPeg.fillColor = PixelPalette.cardUI
            leftPeg.strokeColor = PixelPalette.inkUI
            leftPeg.lineWidth = 1
            leftPeg.position = CGPoint(x: width * 0.048, y: pegY)
            leftPeg.zPosition = 3
            boardLayer.addChild(leftPeg)

            let rightPeg = SKShapeNode(
                rectOf: CGSize(width: pegSize, height: pegSize),
                cornerRadius: 0
            )
            rightPeg.fillColor = PixelPalette.cardUI
            rightPeg.strokeColor = PixelPalette.inkUI
            rightPeg.lineWidth = 1
            rightPeg.position = CGPoint(x: width * 0.162, y: pegY)
            rightPeg.zPosition = 3
            boardLayer.addChild(rightPeg)
        }

        for fretIndex in 0..<13 {
            let fretX: CGFloat = neckStart + (neckEnd - neckStart) * CGFloat(fretIndex) / 12.0
            let fret = SKShapeNode(
                rect: CGRect(
                    x: fretX,
                    y: neckY - neckHeight / 2 + 5,
                    width: 1.5,
                    height: neckHeight - 10
                ),
                cornerRadius: 0
            )
            fret.fillColor = PixelPalette.cardUI.withAlphaComponent(0.75)
            fret.strokeColor = .clear
            fret.zPosition = 3
            boardLayer.addChild(fret)
        }

        let bodyShadow = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth, height: bodyHeight)
        )
        bodyShadow.fillColor = PixelPalette.shadowUI
        bodyShadow.strokeColor = .clear
        bodyShadow.position = CGPoint(
            x: bodyCenterX,
            y: stringCenterY - shadowOffset
        )
        bodyShadow.zPosition = 2
        boardLayer.addChild(bodyShadow)

        let lowerBody = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth, height: bodyHeight)
        )
        lowerBody.fillColor = PixelPalette.accentUI
        lowerBody.strokeColor = PixelPalette.inkUI
        lowerBody.lineWidth = 2
        lowerBody.position = CGPoint(x: bodyCenterX, y: stringCenterY)
        lowerBody.zPosition = 3
        boardLayer.addChild(lowerBody)

        let upperBody = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth * 0.62, height: bodyHeight * 0.46)
        )
        upperBody.fillColor = PixelPalette.accentUI
        upperBody.strokeColor = PixelPalette.inkUI
        upperBody.lineWidth = 2
        upperBody.position = CGPoint(
            x: bodyCenterX - bodyWidth * 0.18,
            y: stringCenterY
        )
        upperBody.zPosition = 3
        boardLayer.addChild(upperBody)

        let pickguard = SKShapeNode(
            ellipseOf: CGSize(width: bodyWidth * 0.42, height: bodyHeight * 0.30)
        )
        pickguard.fillColor = PixelPalette.secondaryUI
        pickguard.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.55)
        pickguard.lineWidth = 1.2
        pickguard.position = CGPoint(
            x: bodyCenterX + bodyWidth * 0.05,
            y: stringCenterY - bodyHeight * 0.02
        )
        pickguard.zPosition = 4
        boardLayer.addChild(pickguard)

        for pickupIndex in 0..<2 {
            let pickup = SKShapeNode(
                rectOf: CGSize(width: bodyWidth * 0.22, height: max(10, neckHeight * 0.13)),
                cornerRadius: 2
            )
            pickup.fillColor = PixelPalette.inkUI
            pickup.strokeColor = PixelPalette.cardUI.withAlphaComponent(0.55)
            pickup.lineWidth = 1
            pickup.position = CGPoint(
                x: bodyCenterX - bodyWidth * 0.03,
                y: stringCenterY + (pickupIndex == 0 ? stringSpacing * 0.75 : -stringSpacing * 0.75)
            )
            pickup.zPosition = 5
            boardLayer.addChild(pickup)
        }

        let knobSize: CGFloat = max(5, min(10, width * 0.009))
        for knobIndex in 0..<3 {
            let knob = SKShapeNode(
                rectOf: CGSize(width: knobSize, height: knobSize),
                cornerRadius: 0
            )
            let knobColor: UIColor = knobIndex % 2 == 0 ? PixelPalette.cardUI : PixelPalette.inkUI
            knob.fillColor = knobColor
            knob.strokeColor = PixelPalette.inkUI
            knob.lineWidth = 1
            knob.position = CGPoint(
                x: bodyCenterX + bodyWidth * 0.30,
                y: stringCenterY - CGFloat(knobIndex) * knobSize * 1.5
            )
            knob.zPosition = 5
            boardLayer.addChild(knob)
        }

        let bandWidth: CGFloat = bodyEndX - headX
        for index in 0..<6 {
            let bandRect = CGRect(
                x: headX,
                y: stringYs[index] - stringSpacing * 0.42,
                width: bandWidth,
                height: stringSpacing * 0.84
            )
            let band = SKShapeNode(rect: bandRect, cornerRadius: 5)
            band.fillColor = index % 2 == 0
                ? PixelPalette.cardUI.withAlphaComponent(0.07)
                : PixelPalette.secondaryUI.withAlphaComponent(0.08)
            band.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.10)
            band.lineWidth = 1
            band.zPosition = 4
            boardLayer.addChild(band)
        }
    }

    private func buildStrings(width: CGFloat) {
        for index in 0..<6 {
            let y: CGFloat = stringYs[index]
            let thickness: CGFloat = index == 0 ? 2.4 : (index == 5 ? 1.2 : 1.8)
            let moveNode = SKNode()
            moveNode.zPosition = 10
            stringLayer.addChild(moveNode)

            let shadowLine = SKShapeNode(
                rectOf: CGSize(width: bridgeX - headX, height: thickness + 2.2),
                cornerRadius: 0
            )
            shadowLine.fillColor = PixelPalette.inkUI.withAlphaComponent(0.55)
            shadowLine.strokeColor = .clear
            shadowLine.position = CGPoint(
                x: (headX + bridgeX) / 2,
                y: y
            )
            moveNode.addChild(shadowLine)

            let stringLine = SKShapeNode(
                rectOf: CGSize(width: bridgeX - headX, height: thickness),
                cornerRadius: 0
            )
            stringLine.fillColor = PixelPalette.cardUI
            stringLine.strokeColor = .clear
            stringLine.position = CGPoint(
                x: (headX + bridgeX) / 2,
                y: y
            )
            stringLine.zPosition = 1
            moveNode.addChild(stringLine)

            let pressNode = SKShapeNode(
                rectOf: CGSize(width: bridgeX - headX, height: max(8, stringSpacing * 0.22)),
                cornerRadius: 2
            )
            pressNode.fillColor = PixelPalette.accentUI
            pressNode.strokeColor = .clear
            pressNode.alpha = 0
            pressNode.position = CGPoint(x: (headX + bridgeX) / 2, y: y)
            pressNode.zPosition = 9
            stringLayer.addChild(pressNode)

            let glowNode = SKShapeNode(
                rectOf: CGSize(width: bridgeX - headX, height: thickness + 7),
                cornerRadius: 2
            )
            glowNode.fillColor = .clear
            glowNode.strokeColor = PixelPalette.accentUI
            glowNode.lineWidth = 1
            glowNode.alpha = 0
            glowNode.position = CGPoint(x: (headX + bridgeX) / 2, y: y)
            glowNode.zPosition = 8
            stringLayer.addChild(glowNode)

            stringMoveNodes.append(moveNode)
            stringPressNodes.append(pressNode)
            laneGlowNodes.append(glowNode)
        }
    }

    private func buildStringLabels(sideInset: CGFloat) {
        for index in 0..<6 {
            let string: GuitarString = GuitarString.displayOrder[index]
            let label = SKLabelNode(
                fontNamed: monospacedFontName(size: 10, weight: .semibold)
            )
            label.text = "\(string.keyboardKey) · \(string.rawValue) \(string.openName)"
            label.fontSize = 10
            label.fontColor = PixelPalette.inkUI
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: sideInset, y: stringYs[index])
            label.zPosition = 5
            boardLayer.addChild(label)
        }
    }

    private func buildBridge(width: CGFloat) {
        let bridgeHeight: CGFloat = stringSpacing * 5.6
        let bridge = SKShapeNode(
            rect: CGRect(
                x: bridgeX - 8,
                y: stringCenterY - bridgeHeight / 2,
                width: 18,
                height: bridgeHeight
            ),
            cornerRadius: 2
        )
        bridge.fillColor = PixelPalette.inkUI
        bridge.strokeColor = PixelPalette.cardUI.withAlphaComponent(0.75)
        bridge.lineWidth = 1
        bridge.zPosition = 6
        boardLayer.addChild(bridge)

        let judgePath = CGMutablePath()
        let lineTop: CGFloat = stringCenterY + stringSpacing * 2.5 + 20
        let lineBottom: CGFloat = stringCenterY - stringSpacing * 2.5 - 20
        judgePath.move(to: CGPoint(x: bridgeX, y: lineTop))
        judgePath.addLine(to: CGPoint(x: bridgeX, y: lineBottom))

        let judgeLine = SKShapeNode(path: judgePath)
        judgeLine.strokeColor = PixelPalette.accentUI
        judgeLine.lineWidth = 2.5
        judgeLine.glowWidth = 0
        judgeLine.zPosition = 7
        boardLayer.addChild(judgeLine)

        for index in 0..<6 {
            let target = SKShapeNode(
                rectOf: CGSize(width: 10, height: max(8, stringSpacing * 0.72)),
                cornerRadius: 2
            )
            target.fillColor = PixelPalette.cardUI
            target.strokeColor = PixelPalette.accentUI
            target.lineWidth = 1.5
            target.alpha = 0.28
            target.position = CGPoint(x: bridgeX, y: stringYs[index])
            target.zPosition = 8
            boardLayer.addChild(target)
            targetNodes.append(target)
        }
    }

    private func buildCountdownPositions(width: CGFloat, height: CGFloat) {
        let labelSize: CGFloat = min(max(width * 0.085, 52), 96)
        let centerY: CGFloat = height * 0.55
        countdownLabel?.fontSize = labelSize
        countdownLabel?.position = CGPoint(x: width / 2, y: centerY)

        let hintSize: CGFloat = min(max(width * 0.014, 11), 17)
        countdownHint?.fontSize = hintSize
        countdownHint?.position = CGPoint(
            x: width / 2,
            y: centerY - labelSize * 0.72
        )
    }

    private func createCountdownLabels() {
        let label = SKLabelNode(fontNamed: fontName(size: 84, weight: .heavy))
        label.fontSize = 84
        label.fontColor = PixelPalette.inkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.alpha = 0
        label.isHidden = true
        overlayLayer.addChild(label)
        countdownLabel = label

        let hint = SKLabelNode(fontNamed: fontName(size: 14, weight: .semibold))
        hint.text = "触屏准备"
        hint.fontSize = 14
        hint.fontColor = PixelPalette.mutedUI
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.isHidden = true
        overlayLayer.addChild(hint)
        countdownHint = hint
    }

    private func syncNoteNodes() {
        guard layoutIsValid, stringYs.count == 6 else { return }
        guard shouldDisplayNotes else {
            if !noteNodes.isEmpty {
                noteLayer.removeAllChildren()
                noteNodes.removeAll(keepingCapacity: true)
            }
            for index in 0..<laneGlowNodes.count {
                laneGlowNodes[index].alpha = 0
            }
            for index in 0..<targetNodes.count {
                targetNodes[index].alpha = 0.28
            }
            return
        }

        let now = session.practiceTime
        var visibleIDs = Set<Int>()
        var upcomingLanes = Set<Int>()

        for note in chart.notes where !session.isResolved(noteID: note.id) {
            let remaining = note.targetTime - now
            guard remaining <= chart.practiceChart.previewDuration + 0.001 else { continue }
            let lane: Int = note.lane
            guard stringYs.indices.contains(lane) else { continue }

            visibleIDs.insert(note.id)
            upcomingLanes.insert(lane)
            let node: SKNode
            if let existing = noteNodes[note.id] {
                node = existing
            } else {
                node = createNoteCue(for: note)
            }
            node.position = CGPoint(
                x: noteX(remaining: remaining),
                y: stringYs[lane]
            )
        }

        let staleIDs = noteNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            noteNodes.removeValue(forKey: id)?.removeFromParent()
        }

        for index in 0..<laneGlowNodes.count {
            laneGlowNodes[index].alpha = upcomingLanes.contains(index) ? 0.42 : 0
        }
        for index in 0..<targetNodes.count {
            targetNodes[index].alpha = upcomingLanes.contains(index) ? 1.0 : 0.28
        }
    }

    private var shouldDisplayNotes: Bool {
        switch session.phase {
        case .playing:
            return true
        case .paused:
            return session.practiceTime > 0
        default:
            return false
        }
    }

    private func createNoteCue(for note: GuitarNote) -> SKNode {
        let container = SKNode()
        container.zPosition = 20

        let line = SKShapeNode(
            rectOf: CGSize(width: 30, height: 3),
            cornerRadius: 0
        )
        line.fillColor = PixelPalette.accentUI
        line.strokeColor = PixelPalette.inkUI
        line.lineWidth = 1
        line.position = .zero
        container.addChild(line)


        let pillWidth: CGFloat = max(46, CGFloat(note.hintText.count) * 7.2)
        let pillHeight: CGFloat = 14
        let pill = SKShapeNode(
            rectOf: CGSize(width: pillWidth, height: pillHeight),
            cornerRadius: 2
        )
        pill.fillColor = PixelPalette.cardUI
        pill.strokeColor = PixelPalette.lineUI
        pill.lineWidth = 1
        pill.position = CGPoint(x: 0, y: 31)
        pill.zPosition = 2
        container.addChild(pill)

        let label = SKLabelNode(fontNamed: fontName(size: 8, weight: .semibold))
        label.text = note.hintText
        label.fontSize = 8
        label.fontColor = PixelPalette.inkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 31)
        label.zPosition = 3
        container.addChild(label)

        noteLayer.addChild(container)
        noteNodes[note.id] = container
        return container
    }

    private func noteX(remaining: TimeInterval) -> CGFloat {
        let preview: TimeInterval = chart.practiceChart.previewDuration
        let progress: CGFloat = CGFloat(min(max(remaining / preview, 0.0), 1.0))
        return bridgeX - progress * (bridgeX - headX)
    }

    private func updateCountdown() {
        guard let label = countdownLabel, let hint = countdownHint else { return }

        switch session.phase {
        case .countdown:
            label.isHidden = false
            hint.isHidden = false
            label.alpha = 1.0
            label.text = "\(max(1, Int(ceil(session.countdownRemaining))))"
            hint.text = "触屏准备"
        case .playing:
            if session.practiceTime < 0.7 {
                label.isHidden = false
                hint.isHidden = true
                label.text = "开始"
                label.alpha = CGFloat(max(0, 1 - session.practiceTime / 0.7))
            } else {
                label.isHidden = true
                hint.isHidden = true
            }
        default:
            label.isHidden = true
            hint.isHidden = true
        }
    }

    private func addBridgeFlash() {
        let top: CGFloat = stringCenterY + stringSpacing * 2.5 + 20
        let bottom: CGFloat = stringCenterY - stringSpacing * 2.5 - 20
        let flash = SKShapeNode(
            rectOf: CGSize(width: 8, height: max(top - bottom, 20)),
            cornerRadius: 0
        )
        flash.fillColor = PixelPalette.accentUI
        flash.strokeColor = .clear
        flash.position = CGPoint(x: bridgeX, y: (top + bottom) / 2)
        flash.alpha = 0.9
        flash.zPosition = 31
        effectLayer.addChild(flash)
        let fade = SKAction.fadeOut(withDuration: 0.22)
        let remove = SKAction.removeFromParent()
        flash.run(.sequence([fade, remove]))
    }

    private func present(_ event: PracticeEvent, now: TimeInterval) {
        guard stringYs.indices.contains(event.lane) else { return }

        if let noteID = event.noteID {
            removeCue(noteID: noteID, judgment: event.judgment)
        }

        if event.judgment.isHit || event.judgment == .empty {
            vibrateString(lane: event.lane, amplitude: event.judgment.isHit ? 4.0 : 2.5)
        }

        addBridgeFlash()

        let feedbackColor: UIColor
        switch event.judgment {
        case .perfect:
            feedbackColor = PixelPalette.accentDarkUI
        case .good:
            feedbackColor = PixelPalette.goodUI
        case .miss:
            feedbackColor = PixelPalette.missUI
        case .empty:
            feedbackColor = PixelPalette.mutedUI
        }

        let labelSize: CGFloat = min(max(size.width * 0.014, 11), 18)
        let label = SKLabelNode(fontNamed: fontName(size: labelSize, weight: .heavy))
        label.text = event.judgment.rawValue
        label.fontSize = labelSize
        label.fontColor = feedbackColor
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(
            x: bridgeX + 26,
            y: stringYs[event.lane] + 12
        )
        label.alpha = 0
        label.zPosition = 32
        effectLayer.addChild(label)

        let show = SKAction.fadeIn(withDuration: 0.04)
        let hold = SKAction.wait(forDuration: event.judgment == .miss ? 0.24 : 0.10)
        let rise = SKAction.moveBy(x: 0, y: 18, duration: 0.28)
        let fade = SKAction.fadeOut(withDuration: 0.28)
        let remove = SKAction.removeFromParent()
        label.run(.sequence([show, hold, .group([rise, fade]), remove]))

        if event.judgment.isHit {
            let count: Int = event.judgment == .perfect ? 5 : 3
            addSquareBurst(lane: event.lane, count: count)
        }
    }

    private func removeCue(noteID: Int, judgment: PracticeJudgment) {
        guard let node = noteNodes.removeValue(forKey: noteID) else { return }
        let shrink = SKAction.scale(to: judgment.isHit ? 0.55 : 0.85, duration: 0.13)
        let fade = SKAction.fadeOut(withDuration: 0.13)
        let remove = SKAction.removeFromParent()
        if judgment.isHit {
            let jump = SKAction.moveBy(x: 0, y: 9, duration: 0.10)
            node.run(.sequence([jump, .group([shrink, fade]), remove]))
        } else {
            node.run(.sequence([.group([shrink, fade]), remove]))
        }
    }

    private func addSquareBurst(lane: Int, count: Int) {
        guard stringYs.indices.contains(lane) else { return }
        let offsets: [CGFloat] = [-12, -6, 0, 6, 12]
        let maxCount: Int = min(count, offsets.count)
        let baseY: CGFloat = stringYs[lane]
        for index in 0..<maxCount {
            let particleSize: CGFloat = index % 2 == 0 ? 4 : 3
            let particle = SKShapeNode(circleOfRadius: particleSize / 2)
            particle.fillColor = index % 2 == 0 ? PixelPalette.accentUI : PixelPalette.inkUI
            particle.strokeColor = .clear
            particle.position = CGPoint(
                x: bridgeX + offsets[index],
                y: baseY
            )
            particle.alpha = 0.95
            particle.zPosition = 33
            effectLayer.addChild(particle)

            let move = SKAction.moveBy(
                x: offsets[index] * 0.6,
                y: 12 + CGFloat(index % 2) * 5,
                duration: 0.22
            )
            let fade = SKAction.fadeOut(withDuration: 0.22)
            particle.run(.sequence([.group([move, fade]), .removeFromParent()]))
        }
    }

    private func laneIndex(at point: CGPoint) -> Int? {
        for index in stringHitRects.indices where stringHitRects[index].contains(point) {
            return index
        }
        return nil
    }

    private func monospacedFontName(size: CGFloat, weight: UIFont.Weight) -> String {
        return fontName(size: size, weight: weight)
    }

    private func fontName(size: CGFloat, weight: UIFont.Weight) -> String {
        let pingFangName: String
        if weight == .black || weight == .heavy || weight == .bold {
            pingFangName = "PingFangSC-Semibold"
        } else if weight == .semibold || weight == .medium {
            pingFangName = "PingFangSC-Medium"
        } else {
            pingFangName = "PingFangSC-Regular"
        }
        if let font = UIFont(name: pingFangName, size: size) {
            return font.fontName
        }
        return UIFont.systemFont(ofSize: size, weight: weight).fontName
    }
}
