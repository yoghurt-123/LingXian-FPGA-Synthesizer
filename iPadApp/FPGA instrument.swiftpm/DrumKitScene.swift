import Foundation
import SpriteKit
import UIKit

final class DrumKitScene: SKScene {
    private unowned let session: PracticeSession
    private let chart: DrumKitChart
    private let audio: DrumKitSoundEngine

    private let boardLayer = SKNode()
    private let kitLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let overlayLayer = SKNode()

    private var noteNodes: [Int: SKShapeNode] = [:]
    private var hitZones: [DrumHitZone] = []
    private var instrumentNodes: [Int: SKNode] = [:]
    private var instrumentCenters: [Int: CGPoint] = [:]
    private var instrumentRingSizes: [Int: CGSize] = [:]
    private var pressNodes: [Int: SKShapeNode] = [:]
    private var pressedCounts: [Int] = Array(repeating: 0, count: DrumKitInstrument.allCases.count)
    private var activeTouches: [ObjectIdentifier: Int] = [:]

    private var unit: CGFloat = 30
    private var countdownLabel: SKLabelNode?
    private var countdownHint: SKLabelNode?
    private var lastRunID = -1
    private var lastPhase: PracticePhase = .idle
    private var didSetup = false
    private var layoutIsValid = false

    init(session: PracticeSession, chart: DrumKitChart, audio: DrumKitSoundEngine) {
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
        kitLayer.zPosition = 10
        noteLayer.zPosition = 20
        effectLayer.zPosition = 30
        overlayLayer.zPosition = 100

        addChild(boardLayer)
        addChild(kitLayer)
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
            present(event)
        }

        syncNoteNodes()
        updateCountdown()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let canPlaySound: Bool = session.phase == .playing || session.phase == .countdown
        var lanes: [Int] = []
        var seen = Set<Int>()
        var latestTimestamp: TimeInterval = 0

        for touch in touches {
            let point = touch.location(in: self)
            guard let instrument = hitInstrument(at: point) else { continue }
            let lane: Int = instrument.rawValue
            let touchKey = ObjectIdentifier(touch)
            if activeTouches[touchKey] == nil {
                activeTouches[touchKey] = lane
                if pressedCounts.indices.contains(lane) {
                    pressedCounts[lane] += 1
                }
            }
            if seen.insert(lane).inserted {
                lanes.append(lane)
                if canPlaySound {
                    audio.play(instrument: instrument)
                }
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
            let key = ObjectIdentifier(touch)
            guard let lane = activeTouches.removeValue(forKey: key) else { continue }
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
        guard pressNodes.count == pressedCounts.count else { return }
        for index in pressedCounts.indices {
            guard let node = pressNodes[index] else { continue }
            node.alpha = pressedCounts[index] > 0 ? 0.50 : 0
        }
    }

    private func handlePhaseChange(to newPhase: PracticePhase) {
        if newPhase == .paused {
            kitLayer.speed = 0
            noteLayer.speed = 0
            effectLayer.speed = 0
            audio.stopAll()
            clearInputState()
            return
        }

        kitLayer.speed = 1
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
        kitLayer.speed = 1
        noteLayer.speed = 1
        effectLayer.speed = 1
        audio.stopAll()
        resetInstrumentAnimations()
        clearInputState()
    }

    private func resetInstrumentAnimations() {
        for (lane, container) in instrumentNodes {
            guard let center = instrumentCenters[lane] else { continue }
            container.removeAllActions()
            container.setScale(1.0)
            container.zRotation = 0
            container.position = center
        }
    }

    private func rebuildLayout() {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 420, height > 260 else {
            layoutIsValid = false
            hitZones.removeAll(keepingCapacity: true)
            noteLayer.removeAllChildren()
            noteNodes.removeAll(keepingCapacity: true)
            clearInputState()
            return
        }

        unit = min(width * 0.055, height * 0.105)
        let layouts: [DrumLayout] = makeLayouts(width: width, height: height)
        hitZones = layouts.map { layout in
            DrumHitZone(
                instrument: layout.instrument,
                center: layout.center,
                radiusX: layout.rx * (layout.instrument.isCymbalLike ? 1.22 : 1.08),
                radiusY: layout.ry * (layout.instrument.isCymbalLike ? 1.25 : 1.10),
                priority: layout.priority
            )
        }
        hitZones.sort { $0.priority > $1.priority }

        boardLayer.removeAllChildren()
        kitLayer.removeAllChildren()
        noteLayer.removeAllChildren()
        noteNodes.removeAll(keepingCapacity: true)
        effectLayer.removeAllChildren()
        instrumentNodes.removeAll(keepingCapacity: true)
        instrumentCenters.removeAll(keepingCapacity: true)
        instrumentRingSizes.removeAll(keepingCapacity: true)
        pressNodes.removeAll(keepingCapacity: true)

        for layout in layouts {
            buildInstrument(layout: layout)
        }

        let widthScale: CGFloat = min(max(width * 0.085, 50), 92)
        countdownLabel?.fontSize = widthScale
        countdownLabel?.position = CGPoint(x: width / 2, y: height * 0.55)

        let hintSize: CGFloat = min(max(width * 0.014, 11), 17)
        countdownHint?.fontSize = hintSize
        countdownHint?.position = CGPoint(x: width / 2, y: height * 0.55 - widthScale * 0.72)

        syncNoteNodes()
        updatePressState()
        layoutIsValid = true
    }

    private func makeLayouts(width: CGFloat, height: CGFloat) -> [DrumLayout] {
        let u: CGFloat = unit
        return [
            DrumLayout(instrument: .crash, center: CGPoint(x: width * 0.20, y: height * 0.80), rx: u * 1.55, ry: u * 0.34, priority: 100),
            DrumLayout(instrument: .ride, center: CGPoint(x: width * 0.82, y: height * 0.78), rx: u * 1.45, ry: u * 0.32, priority: 98),
            DrumLayout(instrument: .openHat, center: CGPoint(x: width * 0.15, y: height * 0.60), rx: u * 0.95, ry: u * 0.27, priority: 96),
            DrumLayout(instrument: .closedHat, center: CGPoint(x: width * 0.15, y: height * 0.43), rx: u * 0.90, ry: u * 0.25, priority: 95),
            DrumLayout(instrument: .snare, center: CGPoint(x: width * 0.33, y: height * 0.50), rx: u * 1.20, ry: u * 0.46, priority: 82),
            DrumLayout(instrument: .highTom, center: CGPoint(x: width * 0.39, y: height * 0.73), rx: u * 1.05, ry: u * 0.43, priority: 74),
            DrumLayout(instrument: .midTom, center: CGPoint(x: width * 0.54, y: height * 0.79), rx: u * 1.10, ry: u * 0.45, priority: 72),
            DrumLayout(instrument: .lowTom, center: CGPoint(x: width * 0.68, y: height * 0.55), rx: u * 1.10, ry: u * 0.45, priority: 70),
            DrumLayout(instrument: .kick, center: CGPoint(x: width * 0.50, y: height * 0.22), rx: u * 2.00, ry: u * 0.85, priority: 50)
        ]
    }

    private func buildInstrument(layout: DrumLayout) {
        let instrument = layout.instrument
        let center = layout.center
        let rx = layout.rx
        let ry = layout.ry
        let isCymbal = instrument.isCymbalLike

        let stand = SKShapeNode(
            rectOf: CGSize(width: 3, height: ry * 2.4),
            cornerRadius: 0
        )
        stand.fillColor = PixelPalette.inkUI.withAlphaComponent(0.35)
        stand.strokeColor = .clear
        stand.position = CGPoint(x: center.x, y: center.y - ry * 1.5)
        stand.zPosition = 0
        boardLayer.addChild(stand)

        let container = SKNode()
        container.position = center
        container.zPosition = CGFloat(10 + Int((1 - center.y / max(size.height, 1)) * 10))
        kitLayer.addChild(container)

        let shadow = SKShapeNode(
            ellipseOf: CGSize(width: rx * 2, height: (isCymbal ? ry : ry * 0.8) * 2)
        )
        shadow.fillColor = PixelPalette.shadowUI
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -3)
        shadow.zPosition = 1
        container.addChild(shadow)

        if isCymbal {
            let cymbal = SKShapeNode(
                ellipseOf: CGSize(width: rx * 2, height: ry * 2)
            )
            cymbal.fillColor = instrument == .openHat || instrument == .crash
                ? PixelPalette.accentUI.withAlphaComponent(0.80)
                : PixelPalette.secondaryUI
            cymbal.strokeColor = PixelPalette.inkUI
            cymbal.lineWidth = 1.5
            cymbal.zPosition = 2
            container.addChild(cymbal)

            let bell = SKShapeNode(
                ellipseOf: CGSize(width: rx * 0.34, height: ry * 0.7)
            )
            bell.fillColor = PixelPalette.cardUI
            bell.strokeColor = PixelPalette.inkUI.withAlphaComponent(0.5)
            bell.lineWidth = 1
            bell.zPosition = 3
            container.addChild(bell)
        } else {
            let shell = SKShapeNode(
                rectOf: CGSize(width: rx * 1.80, height: ry * 1.55),
                cornerRadius: 3
            )
            shell.fillColor = PixelPalette.accentDarkUI
            shell.strokeColor = PixelPalette.inkUI
            shell.lineWidth = 1.2
            shell.position = CGPoint(x: 0, y: -ry * 0.55)
            shell.zPosition = 2
            container.addChild(shell)

            let skin = SKShapeNode(
                ellipseOf: CGSize(width: rx * 2, height: ry * 2)
            )
            skin.fillColor = PixelPalette.cardUI
            skin.strokeColor = PixelPalette.inkUI
            skin.lineWidth = 1.5
            skin.position = .zero
            skin.zPosition = 3
            container.addChild(skin)

            let rim = SKShapeNode(
                ellipseOf: CGSize(width: rx * 1.84, height: ry * 1.76)
            )
            rim.fillColor = .clear
            rim.strokeColor = PixelPalette.accentUI.withAlphaComponent(0.65)
            rim.lineWidth = 1
            rim.zPosition = 4
            container.addChild(rim)
        }

        let pillWidth: CGFloat = instrument == .openHat || instrument == .closedHat ? 30 : max(38, rx * 0.8)
        let pillHeight: CGFloat = 15
        let pill = SKShapeNode(
            rectOf: CGSize(width: pillWidth, height: pillHeight),
            cornerRadius: 2
        )
        pill.fillColor = PixelPalette.cardUI.withAlphaComponent(0.92)
        pill.strokeColor = PixelPalette.lineUI
        pill.lineWidth = 1
        pill.position = .zero
        pill.zPosition = 6
        container.addChild(pill)

        let fontSize: CGFloat = instrument == .openHat || instrument == .closedHat ? 12 : 10
        let label = SKLabelNode(fontNamed: fontName(size: fontSize, weight: .bold))
        label.text = instrument.shortLabel
        label.fontSize = fontSize
        label.fontColor = PixelPalette.inkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 7
        container.addChild(label)

        let press = SKShapeNode(
            ellipseOf: CGSize(width: rx * 2, height: ry * 2)
        )
        press.fillColor = PixelPalette.accentUI
        press.strokeColor = PixelPalette.accentUI
        press.lineWidth = 2
        press.alpha = 0
        press.zPosition = 5
        container.addChild(press)

        instrumentNodes[instrument.rawValue] = container
        instrumentCenters[instrument.rawValue] = center
        instrumentRingSizes[instrument.rawValue] = CGSize(width: rx * 2, height: ry * 2)
        pressNodes[instrument.rawValue] = press
    }

    private func createCountdownLabels() {
        let label = SKLabelNode(fontNamed: fontName(size: 84, weight: .heavy))
        label.fontSize = 84
        label.fontColor = PixelPalette.inkUI
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
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
        guard layoutIsValid else { return }
        guard shouldDisplayNotes else {
            if !noteNodes.isEmpty {
                noteLayer.removeAllChildren()
                noteNodes.removeAll(keepingCapacity: true)
            }
            return
        }

        let now = session.practiceTime
        var visible = Set<Int>()

        for note in chart.notes where !session.isResolved(noteID: note.id) {
            let remaining = note.targetTime - now
            guard remaining <= chart.practiceChart.previewDuration + 0.001 else { continue }
            guard let center = instrumentCenters[note.lane],
                  let ringSize = instrumentRingSizes[note.lane] else {
                continue
            }

            visible.insert(note.id)
            let ring: SKShapeNode
            if let existing = noteNodes[note.id] {
                ring = existing
            } else {
                ring = createRing(size: ringSize)
                ring.position = center
                ring.zPosition = 20
                noteLayer.addChild(ring)
                noteNodes[note.id] = ring
            }

            let preview: TimeInterval = chart.practiceChart.previewDuration
            let progress: CGFloat = CGFloat(min(max(remaining / preview, 0.0), 1.0))
            let scale: CGFloat = 1.0 + 0.45 * progress
            ring.setScale(scale)
            ring.alpha = remaining < 0.25 ? 1.0 : 0.85
        }

        let stale = noteNodes.keys.filter { !visible.contains($0) }
        for id in stale {
            noteNodes.removeValue(forKey: id)?.removeFromParent()
        }
    }

    private func createRing(size: CGSize) -> SKShapeNode {
        let ring = SKShapeNode(ellipseOf: size)
        ring.fillColor = .clear
        ring.strokeColor = PixelPalette.accentUI
        ring.lineWidth = 2.5
        ring.glowWidth = 0
        return ring
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

    private func updateCountdown() {
        guard let label = countdownLabel, let hint = countdownHint else { return }
        switch session.phase {
        case .countdown:
            label.isHidden = false
            hint.isHidden = false
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

    private func present(_ event: PracticeEvent) {
        guard let instrument = DrumKitInstrument(rawValue: event.lane) else { return }

        if let noteID = event.noteID {
            removeRing(noteID: noteID, judgment: event.judgment)
        }

        if event.judgment != .miss {
            animateInstrument(instrument)
        }
        addFlash(instrument: instrument, judgment: event.judgment)

        let color: UIColor
        switch event.judgment {
        case .perfect: color = PixelPalette.accentDarkUI
        case .good: color = PixelPalette.goodUI
        case .miss: color = PixelPalette.missUI
        case .empty: color = PixelPalette.mutedUI
        }

        guard let center = instrumentCenters[instrument.rawValue],
              let ringSize = instrumentRingSizes[instrument.rawValue] else {
            return
        }

        let fontSize: CGFloat = min(max(size.width * 0.013, 10), 17)
        let label = SKLabelNode(fontNamed: fontName(size: fontSize, weight: .heavy))
        label.text = event.judgment.rawValue
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(
            x: center.x,
            y: center.y + ringSize.height * 0.5 + 20
        )
        label.alpha = 0
        label.zPosition = 32
        effectLayer.addChild(label)

        let show = SKAction.fadeIn(withDuration: 0.04)
        let hold = SKAction.wait(forDuration: event.judgment == .miss ? 0.26 : 0.10)
        let rise = SKAction.moveBy(x: 0, y: 18, duration: 0.28)
        let fade = SKAction.fadeOut(withDuration: 0.28)
        label.run(.sequence([show, hold, .group([rise, fade]), .removeFromParent()]))

        if event.judgment.isHit {
            addSquareBurst(center: center, count: event.judgment == .perfect ? 5 : 3)
        }
    }

    private func removeRing(noteID: Int, judgment: PracticeJudgment) {
        guard let ring = noteNodes.removeValue(forKey: noteID) else { return }
        let shrink = SKAction.scale(to: judgment.isHit ? 0.65 : 0.9, duration: 0.13)
        let fade = SKAction.fadeOut(withDuration: 0.13)
        ring.run(.sequence([.group([shrink, fade]), .removeFromParent()]))
    }

    private func animateInstrument(_ instrument: DrumKitInstrument) {
        guard let container = instrumentNodes[instrument.rawValue],
              let center = instrumentCenters[instrument.rawValue] else {
            return
        }
        container.removeAllActions()
        container.position = center
        container.setScale(1.0)
        container.zRotation = 0

        if instrument.isCymbalLike {
            let right = SKAction.rotate(byAngle: 0.10, duration: 0.04)
            let left = SKAction.rotate(byAngle: -0.16, duration: 0.07)
            let settle = SKAction.rotate(byAngle: 0.06, duration: 0.04)
            let back = SKAction.rotate(toAngle: 0, duration: 0.05)
            container.run(.sequence([right, left, settle, back]))
        } else if instrument == .kick {
            let down = SKAction.moveBy(x: 0, y: -3, duration: 0.04)
            let up = SKAction.moveBy(x: 0, y: 5, duration: 0.06)
            let settle = SKAction.moveBy(x: 0, y: -2, duration: 0.05)
            container.run(.sequence([down, up, settle]))
        } else {
            let squash = SKAction.scaleY(to: 0.84, duration: 0.045)
            let stretch = SKAction.scaleY(to: 1.05, duration: 0.06)
            let back = SKAction.scaleY(to: 1.0, duration: 0.05)
            container.run(.sequence([squash, stretch, back]))
        }
    }

    private func addFlash(instrument: DrumKitInstrument, judgment: PracticeJudgment) {
        guard let center = instrumentCenters[instrument.rawValue],
              let ringSize = instrumentRingSizes[instrument.rawValue] else {
            return
        }
        let flash = SKShapeNode(ellipseOf: ringSize)
        switch judgment {
        case .miss:
            flash.fillColor = PixelPalette.missUI
        case .empty:
            flash.fillColor = PixelPalette.mutedUI
        default:
            flash.fillColor = PixelPalette.accentUI
        }
        flash.strokeColor = .clear
        flash.alpha = 0.42
        flash.position = center
        flash.zPosition = 31
        effectLayer.addChild(flash)
        let fade = SKAction.fadeOut(withDuration: 0.20)
        flash.run(.sequence([fade, .removeFromParent()]))
    }

    private func addSquareBurst(center: CGPoint, count: Int) {
        let offsets: [CGFloat] = [-10, -5, 0, 5, 10]
        let maxCount: Int = min(count, offsets.count)
        for index in 0..<maxCount {
            let size: CGFloat = index % 2 == 0 ? 4 : 3
            let particle = SKShapeNode(
                rectOf: CGSize(width: size, height: size),
                cornerRadius: 0
            )
            particle.fillColor = index % 2 == 0 ? PixelPalette.accentUI : PixelPalette.inkUI
            particle.strokeColor = .clear
            particle.position = center
            particle.alpha = 0.95
            particle.zPosition = 33
            effectLayer.addChild(particle)
            let move = SKAction.moveBy(
                x: offsets[index] * 0.7,
                y: 12 + CGFloat(index % 3) * 4,
                duration: 0.24
            )
            let fade = SKAction.fadeOut(withDuration: 0.24)
            particle.run(.sequence([.group([move, fade]), .removeFromParent()]))
        }
    }

    private func hitInstrument(at point: CGPoint) -> DrumKitInstrument? {
        for zone in hitZones {
            let dx: CGFloat = (point.x - zone.center.x) / max(zone.radiusX, 1)
            let dy: CGFloat = (point.y - zone.center.y) / max(zone.radiusY, 1)
            if dx * dx + dy * dy <= 1.0 {
                return zone.instrument
            }
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

private struct DrumLayout {
    let instrument: DrumKitInstrument
    let center: CGPoint
    let rx: CGFloat
    let ry: CGFloat
    let priority: Int
}

private struct DrumHitZone {
    let instrument: DrumKitInstrument
    let center: CGPoint
    let radiusX: CGFloat
    let radiusY: CGFloat
    let priority: Int
}