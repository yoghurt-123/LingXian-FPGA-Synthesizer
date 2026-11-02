import Foundation
import SpriteKit
import UIKit

final class DrumGridScene: SKScene {
    private unowned let session: PracticeSession
    private let chart: DrumKitChart
    private let audio: DrumKitSoundEngine

    private let kitLayer = SKNode()
    private let overlayLayer = SKNode()

    private struct Cell {
        let pad: FPGADrumPad
        let rect: CGRect
        var center: CGPoint {
            CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    private var cells: [Cell] = []
    private var cardNodes: [Int: SKShapeNode] = [:]
    private var pressNodes: [Int: SKShapeNode] = [:]
    private var pressedCounts: [Int] = Array(repeating: 0, count: DrumKitInstrument.allCases.count)
    private var activeTouches: [ObjectIdentifier: Int] = [:]
    private var flashUntil: [Int: TimeInterval] = [:]
    private var flashColors: [Int: UIColor] = [:]
    private var dimUntil: [Int: TimeInterval] = [:]

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
        kitLayer.zPosition = 10
        overlayLayer.zPosition = 100
        addChild(kitLayer)
        addChild(overlayLayer)
        kitLayer.isUserInteractionEnabled = false

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
            present(event)
        }

        updateCountdown()
        updatePadVisuals()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let canPlaySound: Bool = session.phase == .playing || session.phase == .countdown
        var lanes: [Int] = []
        var seen = Set<Int>()
        var latestTimestamp: TimeInterval = 0

        for touch in touches {
            let point: CGPoint = touch.location(in: self)
            guard let cell = hitCell(at: point) else { continue }
            let lane: Int = cell.pad.instrument.rawValue
            let key = ObjectIdentifier(touch)
            if activeTouches[key] == nil {
                activeTouches[key] = lane
                if pressedCounts.indices.contains(lane) {
                    pressedCounts[lane] += 1
                }
            }
            if seen.insert(lane).inserted {
                lanes.append(lane)
                if canPlaySound {
                    session.performanceController?.drumHit(
                        instrument: cell.pad.instrument,
                        velocity: 15,
                        local: { audio.play(instrument: cell.pad.instrument, velocity: 15) }
                    )
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
        for index in pressedCounts.indices {
            guard let node = pressNodes[index] else { continue }
            node.alpha = pressedCounts[index] > 0 ? 0.55 : 0
        }
    }

    private func handlePhaseChange(to newPhase: PracticePhase) {
        if newPhase == .paused || newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            session.releasePerformancePage()
        }
        if newPhase == .paused {
            kitLayer.speed = 0
            audio.stopAll()
            clearInputState()
            return
        }

        kitLayer.speed = 1

        if newPhase == .finished || newPhase == .idle || newPhase == .countdown {
            clearInputState()
        }
    }

    private func resetVisualState() {
        kitLayer.speed = 1
        audio.stopAll()
        for (lane, card) in cardNodes {
            guard let cell = cells.first(where: { $0.pad.instrument.rawValue == lane }) else { continue }
            card.removeAllActions()
            card.position = cell.center
            card.setScale(1.0)
            card.alpha = 1
            card.fillColor = PixelPalette.cardUI
            card.strokeColor = PixelPalette.lineUI
            card.lineWidth = 1.4
        }
        flashUntil.removeAll(keepingCapacity: true)
        flashColors.removeAll(keepingCapacity: true)
        dimUntil.removeAll(keepingCapacity: true)
        clearInputState()
    }

    private func rebuildLayout() {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 280, height > 220 else {
            layoutIsValid = false
            cells.removeAll(keepingCapacity: true)
            clearInputState()
            return
        }

        let margin: CGFloat = min(max(min(width, height) * 0.025, 8), 18)
        let gap: CGFloat = min(max(min(width, height) * 0.015, 10), 14)
        let gridWidth: CGFloat = width - margin * 2
        let gridHeight: CGFloat = height - margin * 2
        let cellWidth: CGFloat = (gridWidth - gap * 2) / 3
        let cellHeight: CGFloat = (gridHeight - gap * 2) / 3

        cells.removeAll(keepingCapacity: true)
        for pad in FPGAKeyMap.drumPads.sorted(by: { $0.gridIndex < $1.gridIndex }) {
            let x: CGFloat = margin + CGFloat(pad.gridColumn) * (cellWidth + gap)
            let y: CGFloat = height - margin - CGFloat(pad.gridRow + 1) * cellHeight - CGFloat(pad.gridRow) * gap
            cells.append(Cell(pad: pad, rect: CGRect(x: x, y: y, width: cellWidth, height: cellHeight)))
        }

        kitLayer.removeAllChildren()
        cardNodes.removeAll(keepingCapacity: true)
        pressNodes.removeAll(keepingCapacity: true)

        for cell in cells {
            buildCard(cell: cell)
        }

        let countdownSize: CGFloat = min(max(width * 0.085, 50), 92)
        countdownLabel?.fontSize = countdownSize
        countdownLabel?.position = CGPoint(x: width / 2, y: height * 0.55)
        countdownHint?.fontSize = min(max(width * 0.014, 11), 17)
        countdownHint?.position = CGPoint(x: width / 2, y: height * 0.55 - countdownSize * 0.72)

        updatePressState()
        updatePadVisuals()
        layoutIsValid = true
    }

    private func buildCard(cell: Cell) {
        let rect = cell.rect
        let lane = cell.pad.instrument.rawValue

        let cardSize = CGSize(width: rect.width, height: rect.height)
        let card = SKShapeNode(rectOf: cardSize, cornerRadius: 12)
        card.fillColor = PixelPalette.cardUI
        card.strokeColor = PixelPalette.lineUI
        card.lineWidth = 1.4
        card.position = cell.center
        card.zPosition = 10
        cardNodes[lane] = card
        kitLayer.addChild(card)

        let press = SKShapeNode(rectOf: cardSize, cornerRadius: 12)
        press.fillColor = PixelPalette.accentUI
        press.strokeColor = .clear
        press.alpha = 0
        press.position = cell.center
        press.zPosition = 11
        pressNodes[lane] = press
        kitLayer.addChild(press)

        let keyLabel = SKLabelNode(fontNamed: monoFont(size: 9, weight: .bold))
        keyLabel.text = "小键盘\(cell.pad.keypadNumber)"
        keyLabel.fontSize = 9
        keyLabel.fontColor = PixelPalette.accentDarkUI
        keyLabel.horizontalAlignmentMode = .left
        keyLabel.verticalAlignmentMode = .center
        keyLabel.position = CGPoint(x: rect.minX + 11, y: rect.maxY - 14)
        keyLabel.zPosition = 14
        kitLayer.addChild(keyLabel)

        let nameLabel = SKLabelNode(fontNamed: fontName(size: 15, weight: .heavy))
        nameLabel.text = cell.pad.instrument.displayName
        nameLabel.fontSize = 15
        nameLabel.fontColor = PixelPalette.inkUI
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: rect.minX + 11, y: rect.midY - 2)
        nameLabel.zPosition = 14
        kitLayer.addChild(nameLabel)

        let subLabel = SKLabelNode(fontNamed: monoFont(size: 8, weight: .medium))
        subLabel.text = "\(cell.pad.instrument.shortLabel) · \(cell.pad.instrument.isCymbalLike ? "镲片" : "鼓")"
        subLabel.fontSize = 8
        subLabel.fontColor = PixelPalette.mutedUI
        subLabel.horizontalAlignmentMode = .left
        subLabel.verticalAlignmentMode = .center
        subLabel.position = CGPoint(x: rect.minX + 11, y: rect.midY - 21)
        subLabel.zPosition = 14
        kitLayer.addChild(subLabel)

        addGlyph(instrument: cell.pad.instrument, rect: rect)
    }

    private func addGlyph(instrument: DrumKitInstrument, rect: CGRect) {
        let size: CGFloat = min(max(rect.height * 0.28, 18), 36)
        let x: CGFloat = rect.maxX - size - 12
        let y: CGFloat = rect.midY

        if instrument.isCymbalLike {
            let cymbal = SKShapeNode(ellipseOf: CGSize(width: size * 1.6, height: size * 0.42))
            cymbal.fillColor = PixelPalette.accentUI
            cymbal.strokeColor = PixelPalette.inkUI
            cymbal.lineWidth = 1
            cymbal.position = CGPoint(x: x, y: y + size * 0.18)
            cymbal.zPosition = 14
            kitLayer.addChild(cymbal)

            let stand = SKShapeNode(rectOf: CGSize(width: 2, height: size * 0.8))
            stand.fillColor = PixelPalette.inkUI
            stand.strokeColor = .clear
            stand.position = CGPoint(x: x, y: y - size * 0.38)
            stand.zPosition = 14
            kitLayer.addChild(stand)
        } else {
            let shell = SKShapeNode(
                rectOf: CGSize(width: size * 1.4, height: size * 0.9),
                cornerRadius: 3
            )
            shell.fillColor = PixelPalette.accentDarkUI
            shell.strokeColor = PixelPalette.inkUI
            shell.lineWidth = 1
            shell.position = CGPoint(x: x, y: y)
            shell.zPosition = 14
            kitLayer.addChild(shell)

            let skin = SKShapeNode(ellipseOf: CGSize(width: size * 1.4, height: size * 0.4))
            skin.fillColor = PixelPalette.cardUI
            skin.strokeColor = PixelPalette.inkUI
            skin.lineWidth = 1
            skin.position = CGPoint(x: x, y: y + size * 0.25)
            skin.zPosition = 15
            kitLayer.addChild(skin)
        }
    }

    private func updatePadVisuals() {
        let now = session.practiceTime
        let preview = max(chart.practiceChart.previewDuration, 0.001)
        let goodWindow = chart.practiceChart.goodWindow

        for cell in cells {
            let lane = cell.pad.instrument.rawValue
            guard let card = cardNodes[lane] else { continue }
            var fill = PixelPalette.cardUI
            var stroke = PixelPalette.lineUI
            var lineWidth: CGFloat = 1.4
            card.alpha = 1

            if let flashEnd = flashUntil[lane], flashEnd > now,
               let flashColor = flashColors[lane] {
                fill = blend(PixelPalette.cardUI, flashColor, 0.65)
                stroke = flashColor
                lineWidth = 2.4
            } else if let dimEnd = dimUntil[lane], dimEnd > now {
                card.alpha = 0.68
                stroke = PixelPalette.mutedUI
                lineWidth = 1.2
            } else {
                let remaining = chart.notes
                    .filter { $0.lane == lane && !session.isResolved(noteID: $0.id) }
                    .map { $0.targetTime - now }
                    .filter { $0 >= -goodWindow && $0 <= preview }
                    .min()

                if let remaining {
                    let intensity = CGFloat(min(max(1 - max(remaining, 0) / preview, 0), 1))
                    fill = blend(
                        PixelPalette.cardUI,
                        PixelPalette.secondaryUI,
                        0.08 + 0.38 * intensity
                    )
                    stroke = blend(PixelPalette.lineUI, PixelPalette.accentUI, intensity)
                    lineWidth = 1.4 + 1.2 * intensity
                }
            }

            card.fillColor = fill
            card.strokeColor = stroke
            card.lineWidth = lineWidth
        }
    }

    private func blend(_ first: UIColor, _ second: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        guard first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return second
        }
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
    private func present(_ event: PracticeEvent) {
        guard let instrument = DrumKitInstrument(rawValue: event.lane),
              let cell = cells.first(where: { $0.pad.instrument == instrument }),
              let card = cardNodes[instrument.rawValue] else {
            return
        }

        let now = session.practiceTime
        let color: UIColor
        switch event.judgment {
        case .perfect: color = PixelPalette.accentDarkUI
        case .good: color = PixelPalette.goodUI
        case .miss: color = PixelPalette.missUI
        case .empty: color = PixelPalette.mutedUI
        }

        if event.judgment == .miss {
            dimUntil[instrument.rawValue] = now + 0.28
            flashUntil.removeValue(forKey: instrument.rawValue)
        } else if event.judgment.isHit {
            flashUntil[instrument.rawValue] = now + 0.20
            flashColors[instrument.rawValue] = color
            dimUntil.removeValue(forKey: instrument.rawValue)
        }

        card.fillColor = event.judgment.isHit
            ? blend(PixelPalette.cardUI, color, 0.65)
            : card.fillColor
        card.strokeColor = event.judgment.isHit ? color : card.strokeColor
        card.lineWidth = event.judgment.isHit ? 2.4 : card.lineWidth

        let fontSize: CGFloat = min(max(cell.rect.height * 0.10, 8), 12)
        let label = SKLabelNode(fontNamed: fontName(size: fontSize, weight: .heavy))
        label.text = event.judgment.rawValue
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .center
        label.position = CGPoint(
            x: cell.rect.maxX - 9,
            y: cell.rect.maxY - 13
        )
        label.alpha = 0
        label.zPosition = 15
        label.isUserInteractionEnabled = false
        kitLayer.addChild(label)

        let show = SKAction.fadeIn(withDuration: 0.04)
        let hold = SKAction.wait(forDuration: event.judgment == .miss ? 0.22 : 0.10)
        let fade = SKAction.fadeOut(withDuration: event.judgment == .miss ? 0.22 : 0.16)
        label.run(.sequence([show, hold, fade, .removeFromParent()]))
    }
    private func hitCell(at point: CGPoint) -> Cell? {
        cells.first { $0.rect.contains(point) }
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

    private func monoFont(size: CGFloat, weight: UIFont.Weight) -> String {
        return fontName(size: size, weight: weight)
    }
}