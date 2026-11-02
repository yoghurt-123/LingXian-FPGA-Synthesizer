import SwiftUI
import UIKit

struct TouchRegion: Identifiable, Equatable {
    let id: Int
    let rect: CGRect
}

struct MultiTouchOverlay: UIViewRepresentable {
    let regions: [TouchRegion]
    let onBegan: (Int, Int) -> Void
    let onMoved: (Int, Int, Int?) -> Void
    let onEnded: (Int, Int, Bool) -> Void

    func makeUIView(context: Context) -> TouchTrackingView {
        let view = TouchTrackingView(frame: .zero)
        view.regions = regions
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: TouchTrackingView, context: Context) {
        uiView.regions = regions
        uiView.onBegan = onBegan
        uiView.onMoved = onMoved
        uiView.onEnded = onEnded
    }
}

final class TouchTrackingView: UIView {
    private struct ActiveTouch {
        var token: Int
        var regionID: Int?
    }

    var regions: [TouchRegion] = []
    var onBegan: ((Int, Int) -> Void)?
    var onMoved: ((Int, Int, Int?) -> Void)?
    var onEnded: ((Int, Int, Bool) -> Void)?

    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]
    private static var globalNextToken = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard activeTouches[key] == nil else { continue }
            let point: CGPoint = touch.location(in: self)
            guard let region = region(at: point) else { continue }
            let token = TouchTrackingView.globalNextToken
            TouchTrackingView.globalNextToken += 1
            activeTouches[key] = ActiveTouch(token: token, regionID: region.id)
            onBegan?(token, region.id)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard var active = activeTouches[key] else { continue }
            let oldRegion = active.regionID
            let newRegion = region(at: touch.location(in: self))?.id
            guard oldRegion != newRegion else { continue }
            active.regionID = newRegion
            activeTouches[key] = active
            onMoved?(active.token, oldRegion ?? -1, newRegion)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        release(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        release(touches, cancelled: true)
    }

    private func release(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let active = activeTouches.removeValue(forKey: key) else { continue }
            if let regionID = active.regionID {
                onEnded?(active.token, regionID, cancelled)
            }
        }
    }

    private func region(at point: CGPoint) -> TouchRegion? {
        for region in regions where region.rect.contains(point) {
            return region
        }
        return nil
    }
}