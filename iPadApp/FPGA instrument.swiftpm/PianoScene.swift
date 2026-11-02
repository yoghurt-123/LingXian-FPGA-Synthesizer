import Foundation
import SpriteKit
import UIKit

final class PianoScene: SKScene {
    private unowned let session: PracticeSession
    private let audio: PianoSoundEngine

    private let boardLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let overlayLayer = SKNode()

    private var noteNodes: [Int: SKNode] = [:]
    private var keyFaceNodes: [SKNode] = []
    private var keyPressedNodes: [SKShapeNode] = []
    private var keyFlashNodes: [SKShapeNode] = []
    private var keyFlashDeadlines: [TimeInterval] = Array(
        repeating: 0,
        count: PianoKey.allCases.count
    )
    private var pressedCounts: [Int] = Array(
        repeating: 0,
        count: PianoKey.allCases.count
    )
    private var activeTouches: [ObjectIdentifier: Int] = [:]

    private var hitRects: [CGRect] = []
    private var laneCenters: [CGFloat] = []
    private var laneWidth: CGFloat = 0
    private var keyboardTopY: CGFloat = 0
    private var judgeLineY: CGFloat = 0
    private var fallDistance: CGFloat = 1

    private var countdownLabel: SKLabelNode?
    private var countdownHint: SKLabelNode?
    private var lastRunID = -1
    private var lastPhase: PracticePhase = .idle
    private var didSetup = false
    private var layoutIsValid = false

    init(session: PracticeSession, audio: PianoSoundEngine) {
        self.session = session
        self.audio = audio
        super.init(size: CGSize(width: 1000, height: 640))
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
        noteLayer.zPosition = 10
        effectLayer.zPosition = 20
        overlayLayer.zPosition = 100

        addChild(boardLayer)
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
        updateKeyFlashVisuals(now: currentTime)
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
            let laneWasReleased = pressedCounts.indices.contains(lane)
                ? pressedCounts[lane] == 0
                : true
            if activeTouches[touchKey] == nil {
                activeTouches[touchKey] = lane
                if pressedCounts.indices.contains(lane) {
                    pressedCounts[lane] += 1
                }
            }
            if seenLanes.insert(lane).inserted {
                lanes.append(lane)
                if canPlaySound && laneWasReleased {
                    let key = PianoKey(rawValue: lane)
                    session.performanceController?.pianoDown(
                        lane: lane,
                        keyID: lane,
                        midiNote: key?.midiNote ?? 60,
                        velocity: 15,
                        local: { audio.playKey(index: lane) }
                    )
                }
            }
            latestTimestamp = max(latestTimestamp, touch.timestamp)
        }

        guard !lanes.isEmpty else { return }
        updatePressedVisuals()

        guard session.phase == .playing else { return }
        session.alignInput(to: latestTimestamp)
        guard session.phase == .playing else {
            clearInputState()
            return
        }

        let hitTime: TimeInterval = session.practiceTime
        for lane in lanes {
            session.registerHit(lane: lane, at: hitTime)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches, reason: .release)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches, reason: .cancel)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let latestTimestamp = touches.map(\.timestamp).max() ?? 0
        if session.phase == .playing {
            session.alignInput(to: latestTimestamp)
        }
        let releaseTime = session.practiceTime
        var changed = false
        for touch in touches {
            let touchKey = ObjectIdentifier(touch)
            guard let oldLane = activeTouches[touchKey] else { continue }
            let newLane = laneIndex(at: touch.location(in: self))
            guard newLane != oldLane else { continue }
            activeTouches.removeValue(forKey: touchKey)
            if pressedCounts.indices.contains(oldLane) {
                pressedCounts[oldLane] = max(0, pressedCounts[oldLane] - 1)
            }
            if pressedCounts.indices.contains(oldLane), pressedCounts[oldLane] == 0 {
                session.performanceController?.pianoUp(lane: oldLane, reason: .slideOut)
                session.registerLaneRelease(lane: oldLane, at: releaseTime)
            }
            changed = true
        }
        if changed {
            updatePressedVisuals()
        }
    }

    private func releaseTouches(_ touches: Set<UITouch>, reason: PerformanceReleaseReason) {
        let latestTimestamp = touches.map(\.timestamp).max() ?? 0
        if session.phase == .playing {
            session.alignInput(to: latestTimestamp)
        }
        let releaseTime = session.practiceTime
        for touch in touches {
            let touchKey = ObjectIdentifier(touch)
            guard let lane = activeTouches.removeValue(forKey: touchKey) else { continue }
            if pressedCounts.indices.contains(lane) {
                pressedCounts[lane] = max(0, pressedCounts[lane] - 1)
            }
            if pressedCounts.indices.contains(lane), pressedCounts[lane] == 0 {
                session.performanceController?.pianoUp(lane: lane, reason: reason)
                session.registerLaneRelease(lane: lane, at: releaseTime)
            }
        }
        updatePressedVisuals()
    }

    private func clearInputState() {
        activeTouches.removeAll(keepingCapacity: true)
        for index in pressedCounts.indices {
            pressedCounts[index] = 0
        }
        updatePressedVisuals()
    }

    private func updatePressedVisuals() {
        guard keyFaceNodes.count == pressedCounts.count,
              keyPressedNodes.count == pressedCounts.count else {
            return
        }

        for index in pressedCounts.indices {
            let isPressed: Bool = pressedCounts[index] > 0
            let currentX: CGFloat = keyFaceNodes[index].position.x
            keyFaceNodes[index].position = CGPoint(
                x: currentX,
                y: isPressed ? -3 : 0
            )
            keyPressedNodes[index].alpha = isPressed ? 0.90 : 0
        }
    }

    private func resetFlashVisuals() {
        keyFlashDeadlines = Array(repeating: 0, count: PianoKey.allCases.count)
        for node in keyFlashNodes {
            node.alpha = 0
        }
    }

    private func handlePhaseChange(to newPhase: PracticePhase) {
        if newPhase == .paused || newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            session.releasePerformancePage()
        }
        if newPhase == .paused {
            effectLayer.speed = 0
            noteLayer.speed = 0
            audio.stopAll()
            clearInputState()
            resetFlashVisuals()
            return
        }

        effectLayer.speed = 1
        noteLayer.speed = 1

        if newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            clearInputState()
            resetFlashVisuals()
        }
    }

    private func resetVisualState() {
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()
        effectLayer.speed = 1
        noteLayer.speed = 1
        for layer in [boardLayer, noteLayer, effectLayer] {
            layer.removeAction(forKey: "combo-shake")
            layer.position = .zero
        }
        audio.stopAll()
        clearInputState()
        resetFlashVisuals()
    }

    private func rebuildLayout() {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 200, height > 220 else {
            layoutIsValid = false
            laneCenters.removeAll(keepingCapacity: true)
            hitRects.removeAll(keepingCapacity: true)
            noteLayer.removeAllChildren()
            noteNodes.removeAll(keepingCapacity: true)
            effectLayer.removeAllChildren()
            clearInputState()
            resetFlashVisuals()
            return
        }

        let keyCount: Int = PianoKey.allCases.count
        let sideInset: CGFloat = min(max(width * 0.018, 10), 24)
        let gap: CGFloat = min(max(width * 0.004, 3), 7)
        let gapTotal: CGFloat = gap * CGFloat(keyCount - 1)
        let availableWidth: CGFloat = width - sideInset * 2 - gapTotal
        laneWidth = availableWidth / CGFloat(keyCount)

        let keyboardHeight: CGFloat = min(max(height * 0.27, 118), 230)
        keyboardTopY = keyboardHeight
        judgeLineY = keyboardTopY + 10

        let topY: CGFloat = height - 14
        fallDistance = max(topY - judgeLineY, 100)

        let laneStride: CGFloat = laneWidth + gap
        let halfLane: CGFloat = laneWidth / 2
        laneCenters.removeAll(keepingCapacity: true)
        hitRects.removeAll(keepingCapacity: true)

        for index in 0..<keyCount {
            let offset: CGFloat = CGFloat(index) * laneStride
            let laneLeft: CGFloat = sideInset + offset
            let laneCenter: CGFloat = laneLeft + halfLane
            laneCenters.append(laneCenter)
            let hitRect = CGRect(
                x: laneLeft,
                y: 0,
                width: laneWidth,
                height: keyboardTopY
            )
            hitRects.append(hitRect)
        }

        boardLayer.removeAllChildren()
        keyFaceNodes.removeAll(keepingCapacity: true)
        keyPressedNodes.removeAll(keepingCapacity: true)
        keyFlashNodes.removeAll(keepingCapacity: true)
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()

        for key in PianoKey.allCases {
            let offset: CGFloat = CGFloat(key.rawValue) * laneStride
            let laneLeft: CGFloat = sideInset + offset
            buildLaneAndKey(key: key, laneLeft: laneLeft)
        }

        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: sideInset, y: judgeLineY))
        linePath.addLine(to: CGPoint(x: width - sideInset, y: judgeLineY))

        let line = SKShapeNode(path: linePath)
        line.strokeColor = PixelPalette.accentUI
        line.lineWidth = 2
        line.glowWidth = 0
        line.zPosition = 8
        boardLayer.addChild(line)

        let countdownSize: CGFloat = min(max(width * 0.095, 56), 104)
        let countdownOffset: CGFloat = fallDistance * 0.56
        let countdownY: CGFloat = judgeLineY + countdownOffset
        countdownLabel?.fontSize = countdownSize
        countdownLabel?.position = CGPoint(x: width / 2, y: countdownY)

        let hintSize: CGFloat = min(max(width * 0.016, 12), 19)
        let hintOffset: CGFloat = countdownSize * 0.68
        let hintY: CGFloat = countdownY - hintOffset
        countdownHint?.fontSize = hintSize
        countdownHint?.position = CGPoint(x: width / 2, y: hintY)

        syncNoteNodes()
        updatePressedVisuals()
        layoutIsValid = true
    }

    private func buildLaneAndKey(key: PianoKey, laneLeft: CGFloat) {
        let trackHeight: CGFloat = max(size.height - judgeLineY, 1)
        let trackRect = CGRect(
            x: laneLeft,
            y: judgeLineY,
            width: laneWidth,
            height: trackHeight
        )
        let track = SKShapeNode(
            rect: trackRect,
            cornerRadius: min(10, laneWidth * 0.08)
        )
        track.fillColor = PixelPalette.cardUI
        track.strokeColor = PixelPalette.lineUI
        track.lineWidth = 1
        track.zPosition = 0
        boardLayer.addChild(track)

        let baseInsets: CGFloat = 2
        let baseHeight: CGFloat = max(keyboardTopY - 10, 50)
        let baseRect = CGRect(
            x: laneLeft + baseInsets,
            y: 6,
            width: max(laneWidth - 4, 1),
            height: baseHeight
        )
        let base = SKShapeNode(rect: baseRect, cornerRadius: 7)
        base.fillColor = PixelPalette.inkUI.withAlphaComponent(0.08)
        base.strokeColor = PixelPalette.lineUI
        base.lineWidth = 1
        base.zPosition = 1
        boardLayer.addChild(base)

        let faceInset: CGFloat = 5
        let faceBottom: CGFloat = 12
        let faceHeight: CGFloat = max(keyboardTopY - 20, 44)
        let faceWidth: CGFloat = max(laneWidth - 10, 1)
        let faceRect = CGRect(
            x: faceInset,
            y: faceBottom,
            width: faceWidth,
            height: faceHeight
        )

        let container = SKNode()
        container.position = CGPoint(x: laneLeft, y: 0)
        container.zPosition = 2
        boardLayer.addChild(container)

        let face = SKShapeNode(rect: faceRect, cornerRadius: 6)
        face.fillColor = PixelPalette.cardUI
        face.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.55)
        face.lineWidth = 1.2
        container.addChild(face)

        let accentWidth: CGFloat = max(laneWidth - 18, 1)
        let accentRect = CGRect(
            x: faceInset + 4,
            y: faceBottom + faceHeight - 10,
            width: accentWidth,
            height: 4
        )
        let accent = SKShapeNode(rect: accentRect, cornerRadius: 2)
        accent.fillColor = PixelPalette.accentUI.withAlphaComponent(0.75)
        accent.strokeColor = .clear
        accent.zPosition = 1
        container.addChild(accent)

        let pressed = SKShapeNode(rect: faceRect, cornerRadius: 6)
        pressed.fillColor = PixelPalette.secondaryUI
        pressed.strokeColor = .clear
        pressed.alpha = 0
        pressed.zPosition = 2
        container.addChild(pressed)

        let flash = SKShapeNode(rect: faceRect, cornerRadius: 6)
        flash.fillColor = PixelPalette.accentUI
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.zPosition = 3
        container.addChild(flash)

        let letterSize: CGFloat = min(max(laneWidth * 0.20, 14), 26)
        let noteSize: CGFloat = min(max(laneWidth * 0.11, 9), 13)
        let labelX: CGFloat = laneWidth / 2
        let letterY: CGFloat = faceBottom + faceHeight * 0.22
        let noteY: CGFloat = faceBottom + faceHeight * 0.10

        let letterLabel = SKLabelNode(
            fontNamed: monospacedFontName(size: letterSize, weight: .bold)
        )
        letterLabel.text = key.keyboardLetter
        letterLabel.fontSize = letterSize
        letterLabel.fontColor = PixelPalette.inkUI
        letterLabel.horizontalAlignmentMode = .center
        letterLabel.verticalAlignmentMode = .center
        letterLabel.position = CGPoint(x: labelX, y: letterY)
        letterLabel.zPosition = 4
        container.addChild(letterLabel)

        let noteLabel = SKLabelNode(
            fontNamed: monospacedFontName(size: noteSize, weight: .medium)
        )
        noteLabel.text = key.name
        noteLabel.fontSize = noteSize
        noteLabel.fontColor = PixelPalette.mutedUI
        noteLabel.horizontalAlignmentMode = .center
        noteLabel.verticalAlignmentMode = .center
        noteLabel.position = CGPoint(x: labelX, y: noteY)
        noteLabel.zPosition = 5
        container.addChild(noteLabel)

        keyFaceNodes.append(container)
        keyPressedNodes.append(pressed)
        keyFlashNodes.append(flash)
    }

    private func createCountdownLabels() {
        let label = SKLabelNode(fontNamed: fontName(size: 90, weight: .heavy))
        label.fontSize = 90
        label.fontColor = PixelPalette.inkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.alpha = 0
        label.isHidden = true
        overlayLayer.addChild(label)
        countdownLabel = label

        let hint = SKLabelNode(fontNamed: fontName(size: 16, weight: .semibold))
        hint.text = "触屏准备"
        hint.fontSize = 16
        hint.fontColor = PixelPalette.mutedUI
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.isHidden = true
        overlayLayer.addChild(hint)
        countdownHint = hint
    }

    private func syncNoteNodes() {
        guard laneCenters.count == PianoKey.allCases.count, laneWidth > 0 else { return }

        guard shouldDisplayNotes else {
            if !noteNodes.isEmpty {
                noteLayer.removeAllChildren()
                noteNodes.removeAll(keepingCapacity: true)
            }
            return
        }

        let now = session.practiceTime
        var visibleIDs = Set<Int>()

        for note in session.chart.notes where !session.isResolved(noteID: note.id) {
            guard laneCenters.indices.contains(note.lane) else { continue }
            let remaining = note.targetTime - now
            guard remaining <= session.chart.previewDuration + 0.001 else { continue }

            visibleIDs.insert(note.id)
            let node: SKNode
            if let existingNode = noteNodes[note.id] {
                node = existingNode
            } else {
                node = createNoteNode(for: note)
            }
            if let hold = node as? PianoHoldNoteNode {
                let headRaw = judgeLineY + CGFloat((note.targetTime - now) / session.chart.previewDuration) * fallDistance
                let tailRaw = judgeLineY + CGFloat((note.endTime - now) / session.chart.previewDuration) * fallDistance
                let headY = max(judgeLineY, headRaw)
                let tailY = max(headY, max(judgeLineY, tailRaw))
                hold.position = CGPoint(x: laneCenters[note.lane], y: 0)
                hold.update(
                    headY: headY,
                    tailY: tailY,
                    active: session.isHoldActive(noteID: note.id)
                )
            } else {
                node.position = CGPoint(
                    x: laneCenters[note.lane],
                    y: noteY(remaining: remaining)
                )
            }
        }

        let staleIDs = noteNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            noteNodes.removeValue(forKey: id)?.removeFromParent()
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

    private func createNoteNode(for note: PracticeNote) -> SKNode {
        if note.isHold {
            let hold = PianoHoldNoteNode(width: max(laneWidth - 16, 22))
            hold.zPosition = 10
            noteLayer.addChild(hold)
            noteNodes[note.id] = hold
            return hold
        }

        let noteHeight: CGFloat = min(max(laneWidth * 0.11, 13), 24)
        let noteWidth: CGFloat = max(laneWidth - 16, 22)

        let shape = SKShapeNode(
            rectOf: CGSize(width: noteWidth, height: noteHeight),
            cornerRadius: 8
        )
        shape.fillColor = PixelPalette.inkUI
        shape.strokeColor = .clear
        shape.lineWidth = 0
        shape.glowWidth = 0
        shape.zPosition = 10

        let accentHeight: CGFloat = 3
        let accentWidth: CGFloat = max(noteWidth - 8, 4)
        let accent = SKShapeNode(
            rectOf: CGSize(width: accentWidth, height: accentHeight),
            cornerRadius: 8
        )
        accent.fillColor = PixelPalette.accentUI
        accent.strokeColor = .clear
        accent.position = CGPoint(x: 0, y: noteHeight / 2 - 5)
        accent.zPosition = 1
        shape.addChild(accent)

        noteLayer.addChild(shape)
        noteNodes[note.id] = shape
        return shape
    }

    private func noteY(remaining: TimeInterval) -> CGFloat {
        let progress: CGFloat = CGFloat(remaining / session.chart.previewDuration)
        let rawY: CGFloat = judgeLineY + progress * fallDistance
        return max(judgeLineY - 4, rawY)
    }

    private func updateCountdown() {
        guard let label = countdownLabel, let hint = countdownHint else { return }

        switch session.phase {
        case .countdown:
            label.isHidden = false
            hint.isHidden = false
            label.text = "\(max(1, Int(ceil(session.countdownRemaining))))"

            let fraction = session.countdownRemaining - floor(session.countdownRemaining)
            label.alpha = CGFloat(0.75 + 0.25 * (1.0 - fraction))
            label.setScale(CGFloat(0.88 + 0.12 * (1.0 - fraction)))
            hint.text = "触屏准备"

        case .playing:
            if session.practiceTime < 0.7 {
                label.isHidden = false
                hint.isHidden = true
                label.text = "开始"
                label.alpha = CGFloat(max(0, 1 - session.practiceTime / 0.7))
                label.setScale(1.0)
            } else {
                label.isHidden = true
                hint.isHidden = true
            }

        default:
            label.isHidden = true
            hint.isHidden = true
        }
    }

    private func updateKeyFlashVisuals(now: TimeInterval) {
        guard keyFlashNodes.count == keyFlashDeadlines.count else { return }

        for index in keyFlashNodes.indices {
            let remaining = keyFlashDeadlines[index] - now
            let strength = max(0, min(1, remaining / 0.22))
            keyFlashNodes[index].alpha = CGFloat(strength) * 0.50
        }
    }

    private func present(_ event: PracticeEvent, now: TimeInterval) {
        guard laneCenters.indices.contains(event.lane),
              keyFlashNodes.indices.contains(event.lane),
              keyFlashDeadlines.indices.contains(event.lane) else {
            return
        }

        if let noteID = event.noteID, event.holdPhase != .holdStart {
            dissolveNoteNode(noteID: noteID, judgment: event.judgment)
        }

        let flashColor: UIColor
        switch event.judgment {
        case .miss:
            flashColor = PixelPalette.missUI
        case .empty:
            flashColor = PixelPalette.mutedUI
        default:
            flashColor = PixelPalette.accentUI
        }
        keyFlashNodes[event.lane].fillColor = flashColor
        keyFlashDeadlines[event.lane] = now + 0.22

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

        let labelText: String
        switch event.holdPhase {
        case .holdStart:
            labelText = "按住"
        case .holdComplete:
            labelText = "完成"
        case .holdBreak:
            labelText = "断连"
        case .tap:
            labelText = event.judgment.rawValue
        }

        let fontSize: CGFloat = min(max(laneWidth * 0.13, 11), 19)
        let label = SKLabelNode(fontNamed: fontName(size: fontSize, weight: .heavy))
        label.text = labelText
        label.fontSize = fontSize
        label.fontColor = feedbackColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(
            x: laneCenters[event.lane],
            y: judgeLineY + max(28, laneWidth * 0.18)
        )
        label.alpha = 0
        label.zPosition = 21
        effectLayer.addChild(label)

        let hold: TimeInterval = event.judgment == .miss ? 0.28 : 0.12
        let rise = SKAction.moveBy(x: 0, y: 24, duration: 0.32)
        let fade = SKAction.fadeOut(withDuration: 0.32)
        let showFeedback = SKAction.fadeIn(withDuration: 0.05)
        let holdFeedback = SKAction.wait(forDuration: hold)
        let animateFeedback = SKAction.group([rise, fade])
        let removeFeedback = SKAction.removeFromParent()
        label.run(SKAction.sequence([showFeedback, holdFeedback, animateFeedback, removeFeedback]))

        if event.judgment.isHit {
            if !session.reduceMotion {
                let particleCount: Int = event.judgment == .perfect ? 6 : 4
                addPixelBurst(lane: event.lane, count: particleCount)
                addJudgeRipple(lane: event.lane)
            }
            maybeCelebrateCombo(event)
        }
    }

    private func addJudgeRipple(lane: Int) {
        guard laneCenters.indices.contains(lane) else { return }
        let ripple = SKShapeNode(
            rectOf: CGSize(width: max(laneWidth * 0.55, 16), height: 2),
            cornerRadius: 8
        )
        ripple.fillColor = PixelPalette.accentUI
        ripple.strokeColor = .clear
        ripple.position = CGPoint(x: laneCenters[lane], y: judgeLineY)
        ripple.alpha = 0.9
        ripple.zPosition = 22
        effectLayer.addChild(ripple)

        let expand = SKAction.scaleX(to: 1.55, duration: 0.18)
        let fade = SKAction.fadeOut(withDuration: 0.18)
        ripple.run(SKAction.sequence([.group([expand, fade]), .removeFromParent()]))
    }

    private func maybeCelebrateCombo(_ event: PracticeEvent) {
        guard event.judgment.isHit,
              event.holdPhase == .tap || event.holdPhase == .holdStart else { return }
        let combo = session.stats.combo
        guard combo == 10 || combo == 25 || combo == 50 else { return }
        addComboCelebration(combo)
    }

    private func addComboCelebration(_ combo: Int) {
        let reduced = session.reduceMotion
        let glow = SKShapeNode(rect: CGRect(origin: .zero, size: size), cornerRadius: 8)
        glow.fillColor = PixelPalette.accentUI.withAlphaComponent(reduced ? 0.05 : 0.12)
        glow.strokeColor = .clear
        glow.zPosition = 19
        glow.isUserInteractionEnabled = false
        effectLayer.addChild(glow)
        glow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: reduced ? 0.28 : 0.46),
            SKAction.removeFromParent()
        ]))

        let label = SKLabelNode(fontNamed: fontName(size: 38, weight: .heavy))
        label.text = "\(combo) COMBO"
        label.fontSize = 38
        label.fontColor = PixelPalette.accentDarkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.54)
        label.setScale(0.55)
        label.alpha = 0
        label.zPosition = 50
        label.isUserInteractionEnabled = false
        effectLayer.addChild(label)
        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.06), .scale(to: 1.12, duration: 0.10)]),
            .scale(to: 1.0, duration: 0.08),
            .wait(forDuration: 0.22),
            .group([.moveBy(x: 0, y: 16, duration: 0.24), .fadeOut(withDuration: 0.24)]),
            .removeFromParent()
        ]))

        if !reduced {
            addComboParticles()
            shakeVisualLayers()
        }
    }

    private func addComboParticles() {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.54)
        let offsets: [CGPoint] = [
            CGPoint(x: -52, y: 10), CGPoint(x: -32, y: -18),
            CGPoint(x: -10, y: 26), CGPoint(x: 14, y: -12),
            CGPoint(x: 38, y: 18), CGPoint(x: 58, y: -6),
            CGPoint(x: -46, y: -24), CGPoint(x: 26, y: 30)
        ]
        for (index, offset) in offsets.enumerated() {
            let particleSize: CGFloat = index % 2 == 0 ? 4 : 3
            let particle = SKShapeNode(
                rectOf: CGSize(width: particleSize, height: particleSize),
                cornerRadius: 8
            )
            particle.fillColor = index % 2 == 0 ? PixelPalette.accentUI : PixelPalette.inkUI
            particle.strokeColor = .clear
            particle.position = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            particle.alpha = 0.95
            particle.zPosition = 49
            particle.isUserInteractionEnabled = false
            effectLayer.addChild(particle)
            let move = SKAction.moveBy(
                x: offset.x * 0.55,
                y: 24 + CGFloat(index % 3) * 8,
                duration: 0.32
            )
            let fade = SKAction.fadeOut(withDuration: 0.32)
            particle.run(SKAction.sequence([.group([move, fade]), .removeFromParent()]))
        }
    }

    private func shakeVisualLayers() {
        let shake = SKAction.sequence([
            .moveBy(x: 3, y: -2, duration: 0.025),
            .moveBy(x: -6, y: 4, duration: 0.035),
            .moveBy(x: 4, y: -3, duration: 0.035),
            .moveBy(x: -2, y: 2, duration: 0.030),
            .move(to: .zero, duration: 0.030)
        ])
        for layer in [boardLayer, noteLayer, effectLayer] {
            layer.removeAction(forKey: "combo-shake")
            layer.position = .zero
            layer.run(shake, withKey: "combo-shake")
        }
    }
    private func dissolveNoteNode(noteID: Int, judgment: PracticeJudgment) {
        guard let node = noteNodes.removeValue(forKey: noteID) else { return }
        let targetScale: CGFloat = judgment.isHit ? 0.55 : 0.82
        let shrink = SKAction.scale(to: targetScale, duration: 0.14)
        let fade = SKAction.fadeOut(withDuration: 0.14)
        let group = SKAction.group([shrink, fade])
        let remove = SKAction.removeFromParent()
        node.run(SKAction.sequence([group, remove]))
    }

    private func addPixelBurst(lane: Int, count: Int) {
        guard laneCenters.indices.contains(lane) else { return }
        let offsets: [CGFloat] = [-15, -9, -3, 3, 9, 15]
        let baseX: CGFloat = laneCenters[lane]
        let maxCount: Int = min(count, offsets.count)

        for index in 0..<maxCount {
            let size: CGFloat = index % 2 == 0 ? 4 : 3
            let particle = SKShapeNode(
                rectOf: CGSize(width: size, height: size),
                cornerRadius: 8
            )
            particle.fillColor = index % 2 == 0 ? PixelPalette.accentUI : PixelPalette.inkUI
            particle.strokeColor = .clear
            particle.position = CGPoint(x: baseX + offsets[index], y: judgeLineY)
            particle.alpha = 0.95
            particle.zPosition = 22
            effectLayer.addChild(particle)

            let dx: CGFloat = offsets[index] * 0.55
            let dy: CGFloat = 14 + CGFloat(index % 3) * 4
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.24)
            let fade = SKAction.fadeOut(withDuration: 0.24)
            let animate = SKAction.group([move, fade])
            let remove = SKAction.removeFromParent()
            particle.run(SKAction.sequence([animate, remove]))
        }
    }

    private func laneIndex(at point: CGPoint) -> Int? {
        for (index, rect) in hitRects.enumerated() where rect.contains(point) {
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
