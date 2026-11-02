import SpriteKit
import UIKit

final class PianoHoldNoteNode: SKNode {
    private let head: SKShapeNode
    private let body: SKShapeNode
    private let tail: SKShapeNode
    private let bodyWidth: CGFloat

    init(width: CGFloat) {
        let safeWidth = max(width, 18)
        bodyWidth = max(safeWidth - 8, 12)
        head = SKShapeNode(
            rectOf: CGSize(width: safeWidth, height: 16),
            cornerRadius: 2
        )
        body = SKShapeNode()
        tail = SKShapeNode(
            rectOf: CGSize(width: bodyWidth, height: 5),
            cornerRadius: 1
        )
        super.init()
        isUserInteractionEnabled = false
        head.isUserInteractionEnabled = false
        body.isUserInteractionEnabled = false
        tail.isUserInteractionEnabled = false

        head.zPosition = 2
        body.zPosition = 1
        tail.zPosition = 2
        addChild(body)
        addChild(tail)
        addChild(head)
        applyColor(active: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(headY: CGFloat, tailY: CGFloat, active: Bool) {
        let safeHeadY = max(0, headY)
        let safeTailY = max(safeHeadY, tailY)
        let length = safeTailY - safeHeadY

        head.position = CGPoint(x: 0, y: safeHeadY)
        tail.position = CGPoint(x: 0, y: safeTailY)
        body.position = CGPoint(x: 0, y: safeHeadY)
        body.path = CGPath(
            rect: CGRect(x: -bodyWidth / 2, y: 0, width: bodyWidth, height: length),
            transform: nil
        )
        body.isHidden = length < 1
        applyColor(active: active)
    }

    private func applyColor(active: Bool) {
        let accent = active ? PixelPalette.accentDarkUI : PixelPalette.accentUI
        let fill = active ? PixelPalette.accentDarkUI : PixelPalette.inkUI
        head.fillColor = accent
        head.strokeColor = PixelPalette.inkUI
        head.lineWidth = 1.4
        tail.fillColor = accent
        tail.strokeColor = PixelPalette.inkUI
        tail.lineWidth = 1
        body.fillColor = fill.withAlphaComponent(active ? 0.58 : 0.34)
        body.strokeColor = accent.withAlphaComponent(0.8)
        body.lineWidth = 1
    }
}
