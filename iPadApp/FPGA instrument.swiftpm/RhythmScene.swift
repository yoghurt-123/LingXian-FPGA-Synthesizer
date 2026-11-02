import Foundation
import SpriteKit
import UIKit

final class RhythmScene: SKScene {
    private unowned let session: PracticeSession

    private let boardLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let overlayLayer = SKNode()

    private var noteNodes: [Int: SKNode] = [:]
    private var padFlashNodes: [SKShapeNode] = []
    private var padPressedNodes: [SKShapeNode] = []
    private var pressedCounts: [Int] = Array(repeating: 0, count: DrumLane.allCases.count)
    private var activeTouches: [ObjectIdentifier: Int] = [:]
    private var countdownLabel: SKLabelNode?
    private var countdownHint: SKLabelNode?

    private var laneCenters: [CGFloat] = []
    private var hitRects: [CGRect] = []
    private var laneWidth: CGFloat = 0
    private var judgeLineY: CGFloat = 0
    private var fallDistance: CGFloat = 1
    private var topY: CGFloat = 0

    private var flashDeadlines: [TimeInterval] = [0, 0, 0, 0]
    private var lastRunID = -1
    private var lastPhase: PracticePhase = .idle
    private var didSetup = false
    private var layoutIsValid = false

    init(session: PracticeSession) {
        self.session = session
        super.init(size: CGSize(width: 900, height: 640))
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
        updateFlashes(now: currentTime)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
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
            }
            latestTimestamp = max(latestTimestamp, touch.timestamp)
        }

        guard !lanes.isEmpty else { return }
        updatePressedHighlights()

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
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            let touchKey = ObjectIdentifier(touch)
            guard let lane = activeTouches.removeValue(forKey: touchKey) else { continue }
            if pressedCounts.indices.contains(lane) {
                pressedCounts[lane] = max(0, pressedCounts[lane] - 1)
            }
        }
        updatePressedHighlights()
    }

    private func clearInputState() {
        activeTouches.removeAll(keepingCapacity: true)
        for index in pressedCounts.indices {
            pressedCounts[index] = 0
        }
        updatePressedHighlights()
    }

    private func updatePressedHighlights() {
        guard padPressedNodes.count == pressedCounts.count else { return }
        for index in padPressedNodes.indices {
            let isPressed: Bool = pressedCounts[index] > 0
            padPressedNodes[index].alpha = isPressed ? 0.55 : 0
        }
    }

    private func resetFlashVisuals() {
        flashDeadlines = Array(repeating: 0, count: DrumLane.allCases.count)
        for node in padFlashNodes {
            node.alpha = 0
        }
    }

    private func handlePhaseChange(to newPhase: PracticePhase) {
        if newPhase == .paused {
            effectLayer.speed = 0
            noteLayer.speed = 0
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
        clearInputState()
        resetFlashVisuals()
    }

    private func rebuildLayout() {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 120, height > 160 else {
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

        let sideInset: CGFloat = min(max(width * 0.022, 12), 28)
        let gap: CGFloat = min(max(width * 0.010, 8), 16)
        laneWidth = (width - sideInset * 2 - gap * 3) / 4

        judgeLineY = min(max(height * 0.28, 104), height * 0.38)
        topY = height - 16
        fallDistance = max(topY - judgeLineY, 80)

        // Explicit CGFloat intermediates keep Swift Playgrounds' type checker
        // from exploring a long chain of overloaded numeric operators in map.
        let laneStride: CGFloat = laneWidth + gap
        let halfLane: CGFloat = laneWidth / 2
        let hitHeight: CGFloat = judgeLineY + 10
        laneCenters.removeAll(keepingCapacity: true)
        hitRects.removeAll(keepingCapacity: true)
        for index in 0..<DrumLane.allCases.count {
            let offset: CGFloat = CGFloat(index) * laneStride
            let laneLeft: CGFloat = sideInset + offset
            let laneCenter: CGFloat = laneLeft + halfLane
            laneCenters.append(laneCenter)
            let hitRect = CGRect(x: laneLeft, y: 0, width: laneWidth, height: hitHeight)
            hitRects.append(hitRect)
        }

        boardLayer.removeAllChildren()
        padFlashNodes.removeAll(keepingCapacity: true)
        padPressedNodes.removeAll(keepingCapacity: true)
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()

        for lane in DrumLane.allCases {
            let laneOffset: CGFloat = CGFloat(lane.rawValue) * laneStride
            let laneX: CGFloat = sideInset + laneOffset

            let trackRect = CGRect(
                x: laneX,
                y: judgeLineY,
                width: laneWidth,
                height: max(height - judgeLineY, 1)
            )
            let track = SKShapeNode(rect: trackRect, cornerRadius: min(14, laneWidth * 0.08))
            track.fillColor = lane.color.withAlphaComponent(0.075)
            track.strokeColor = lane.color.withAlphaComponent(0.16)
            track.lineWidth = 1
            track.zPosition = 1
            boardLayer.addChild(track)

            let padTop: CGFloat = max(judgeLineY - 18, 64)
            let padRect = CGRect(
                x: laneX + 2,
                y: 8,
                width: max(laneWidth - 4, 1),
                height: max(padTop - 8, 48)
            )
            let pad = SKShapeNode(rect: padRect, cornerRadius: 16)
            pad.fillColor = lane.color.withAlphaComponent(0.20)
            pad.strokeColor = lane.color.withAlphaComponent(0.85)
            pad.lineWidth = 2
            pad.glowWidth = 0.5
            pad.zPosition = 2
            boardLayer.addChild(pad)

            let flash = SKShapeNode(rect: padRect, cornerRadius: 16)
            flash.fillColor = lane.color
            flash.strokeColor = .clear
            flash.alpha = 0
            flash.zPosition = 3
            boardLayer.addChild(flash)
            padFlashNodes.append(flash)

            let pressed = SKShapeNode(rect: padRect, cornerRadius: 16)
            pressed.fillColor = lane.color
            pressed.strokeColor = .clear
            pressed.alpha = 0
            pressed.zPosition = 3.5
            boardLayer.addChild(pressed)
            padPressedNodes.append(pressed)

            let nameSize: CGFloat = min(max(laneWidth * 0.15, 15), 28)
            let englishSize: CGFloat = min(max(nameSize * 0.48, 9), 13)

            let name = SKLabelNode(fontNamed: fontName(size: nameSize, weight: .bold))
            name.text = lane.name
            name.fontSize = nameSize
            name.fontColor = PixelPalette.inkUI
            name.horizontalAlignmentMode = .center
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: padRect.midX, y: padRect.midY + nameSize * 0.42)
            name.zPosition = 4
            boardLayer.addChild(name)

            let english = SKLabelNode(fontNamed: fontName(size: englishSize, weight: .medium))
            english.text = lane.englishName
            english.fontSize = englishSize
            english.fontColor = lane.color.withAlphaComponent(0.95)
            english.horizontalAlignmentMode = .center
            english.verticalAlignmentMode = .center
            english.position = CGPoint(x: padRect.midX, y: padRect.midY - nameSize * 0.55)
            english.zPosition = 4
            boardLayer.addChild(english)
        }

        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: sideInset, y: judgeLineY))
        linePath.addLine(to: CGPoint(x: width - sideInset, y: judgeLineY))

        let line = SKShapeNode(path: linePath)
        line.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.88)
        line.lineWidth = 2
        line.glowWidth = 3.5
        line.zPosition = 5
        boardLayer.addChild(line)

        let countdownSize: CGFloat = min(max(width * 0.11, 62), 118)
        let countdownOffset: CGFloat = fallDistance * 0.56
        let countdownY: CGFloat = judgeLineY + countdownOffset
        countdownLabel?.fontSize = countdownSize
        countdownLabel?.position = CGPoint(
            x: width / 2,
            y: countdownY
        )

        let hintSize: CGFloat = min(max(width * 0.018, 13), 20)
        let hintOffset: CGFloat = countdownSize * 0.68
        let hintY: CGFloat = countdownY - hintOffset
        countdownHint?.fontSize = hintSize
        countdownHint?.position = CGPoint(
            x: width / 2,
            y: hintY
        )

        syncNoteNodes()
        updatePressedHighlights()
        layoutIsValid = true
    }

    private func createCountdownLabels() {
        let label = SKLabelNode(fontNamed: fontName(size: 96, weight: .heavy))
        label.fontSize = 96
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
        hint.fontColor = PixelPalette.inkUI.withAlphaComponent(0.66)
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.isHidden = true
        overlayLayer.addChild(hint)
        countdownHint = hint
    }

    private func syncNoteNodes() {
        guard laneCenters.count == DrumLane.allCases.count, laneWidth > 0 else { return }

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
            node.position = CGPoint(
                x: laneCenters[note.lane],
                y: noteY(remaining: remaining)
            )
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
        let noteHeight: CGFloat = min(max(laneWidth * 0.13, 16), 30)
        let noteWidth: CGFloat = max(laneWidth - 24, 40)
        let lane = note.drumLane

        let shape = SKShapeNode(
            rectOf: CGSize(width: noteWidth, height: noteHeight),
            cornerRadius: noteHeight / 2
        )
        shape.fillColor = lane.color
        shape.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.78)
        shape.lineWidth = 1.2
        shape.glowWidth = 2.5
        shape.zPosition = 10

        let highlight = SKShapeNode(
            rectOf: CGSize(width: noteWidth * 0.68, height: max(2, noteHeight * 0.16)),
            cornerRadius: 1.5
        )
        highlight.fillColor = PixelPalette.inkUI.withAlphaComponent(0.55)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: 0, y: noteHeight * 0.18)
        shape.addChild(highlight)

        noteLayer.addChild(shape)
        noteNodes[note.id] = shape
        return shape
    }

    private func noteY(remaining: TimeInterval) -> CGFloat {
        let progress = CGFloat(remaining / session.chart.previewDuration)
        let rawY = judgeLineY + progress * fallDistance
        return max(judgeLineY - 16, rawY)
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

    private func updateFlashes(now: TimeInterval) {
        guard padFlashNodes.count == flashDeadlines.count else { return }

        for lane in padFlashNodes.indices {
            let remaining = flashDeadlines[lane] - now
            let strength = max(0, min(1, remaining / 0.22))
            padFlashNodes[lane].alpha = CGFloat(strength) * 0.52
        }
    }

    private func present(_ event: PracticeEvent, now: TimeInterval) {
        guard laneCenters.indices.contains(event.lane),
              padFlashNodes.indices.contains(event.lane),
              flashDeadlines.indices.contains(event.lane),
              let drumLane = DrumLane(rawValue: event.lane) else {
            return
        }

        if let noteID = event.noteID {
            dissolveNoteNode(noteID: noteID, judgment: event.judgment)
        }

        let laneColor = drumLane.color
        let flashColor: UIColor

        switch event.judgment {
        case .miss:
            flashColor = .systemRed
        case .empty:
            flashColor = laneColor.withAlphaComponent(0.65)
        default:
            flashColor = laneColor
        }

        padFlashNodes[event.lane].fillColor = flashColor
        flashDeadlines[event.lane] = now + 0.22

        let feedbackColor: UIColor
        switch event.judgment {
        case .perfect:
            feedbackColor = PixelPalette.accentDarkUI
        case .good:
            feedbackColor = PixelPalette.goodUI
        case .miss:
            feedbackColor = PixelPalette.missUI
        case .empty:
            feedbackColor = UIColor(white: 0.72, alpha: 1.0)
        }

        let fontSize: CGFloat = min(max(laneWidth * 0.12, 15), 23)
        let label = SKLabelNode(fontNamed: fontName(size: fontSize, weight: .heavy))
        label.text = event.judgment.rawValue
        label.fontSize = fontSize
        label.fontColor = feedbackColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(
            x: laneCenters[event.lane],
            y: judgeLineY + max(34, laneWidth * 0.18)
        )
        label.alpha = 0
        label.zPosition = 21
        effectLayer.addChild(label)

        let hold: TimeInterval = event.judgment == .miss ? 0.28 : 0.12
        let rise = SKAction.moveBy(x: 0, y: 26, duration: 0.34)
        let fade = SKAction.fadeOut(withDuration: 0.34)
        let showFeedback: SKAction = SKAction.fadeIn(withDuration: 0.05)
        let holdFeedback: SKAction = SKAction.wait(forDuration: hold)
        let animateFeedback: SKAction = SKAction.group([rise, fade])
        let removeFeedback: SKAction = SKAction.removeFromParent()
        let feedbackActions: [SKAction] = [showFeedback, holdFeedback, animateFeedback, removeFeedback]
        label.run(SKAction.sequence(feedbackActions))

        if event.judgment.isHit {
            addImpactRing(lane: event.lane, color: laneColor, delay: 0, scale: 2.8)
            if event.judgment == .perfect {
                addImpactRing(lane: event.lane, color: laneColor, delay: 0.04, scale: 3.7)
            }
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

    private func addImpactRing(lane: Int, color: UIColor, delay: TimeInterval, scale: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: 7)
        ring.strokeColor = color
        ring.lineWidth = 2.5
        ring.glowWidth = 2
        ring.position = CGPoint(x: laneCenters[lane], y: judgeLineY)
        ring.alpha = 0
        ring.zPosition = 22
        effectLayer.addChild(ring)

        let appear = SKAction.fadeIn(withDuration: 0.04)
        let expand = SKAction.scale(to: scale, duration: 0.30)
        let fade = SKAction.fadeOut(withDuration: 0.30)
        let waitAction: SKAction = SKAction.wait(forDuration: delay)
        let animateRing: SKAction = SKAction.group([expand, fade])
        let removeRing: SKAction = SKAction.removeFromParent()
        let ringActions: [SKAction] = [waitAction, appear, animateRing, removeRing]
        ring.run(SKAction.sequence(ringActions))
    }

    private func laneIndex(at point: CGPoint) -> Int? {
        for (index, rect) in hitRects.enumerated() where rect.contains(point) {
            return index
        }
        return nil
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
