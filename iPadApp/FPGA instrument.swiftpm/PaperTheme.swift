import SwiftUI
import UIKit

enum PaperPalette {
    static let paper = Color(red: 0.945, green: 0.941, blue: 0.925)
    static let paperDeep = Color(red: 0.910, green: 0.902, blue: 0.874)
    static let paperWhite = Color(red: 0.973, green: 0.969, blue: 0.953)
    static let ink = Color(red: 0.212, green: 0.212, blue: 0.196)
    static let inkSoft = Color(red: 0.333, green: 0.325, blue: 0.302)
    static let pencil = Color(red: 0.651, green: 0.639, blue: 0.612)
    static let line = Color(red: 0.788, green: 0.776, blue: 0.745)
    static let red = Color(red: 0.659, green: 0.357, blue: 0.333)
    static let redDeep = Color(red: 0.545, green: 0.278, blue: 0.259)
    static let green = Color(red: 0.314, green: 0.451, blue: 0.396)
    static let blue = Color(red: 0.392, green: 0.486, blue: 0.588)
    static let shadow = Color.black.opacity(0.10)
}


enum PaperOrbitMedia {
    static var candidateBundles: [Bundle] {
        var result: [Bundle] = [Bundle.main]
        result.append(contentsOf: Bundle.allBundles)
        result.append(contentsOf: Bundle.allFrameworks)
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in urls where url.pathExtension == "bundle" {
                if let bundle = Bundle(url: url) {
                    result.append(bundle)
                }
            }
        }
        var seen: Set<String> = []
        return result.filter { bundle in
            let key = bundle.bundleURL.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    static func image(named name: String, extensions: [String] = ["png", "jpg", "jpeg"]) -> Image? {
        for bundle in candidateBundles {
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return Image(uiImage: image)
            }
            for ext in extensions {
                if let url = bundle.url(forResource: name, withExtension: ext),
                   let image = UIImage(contentsOfFile: url.path) {
                    return Image(uiImage: image)
                }
            }
        }
        return nil
    }

    static func url(named name: String, withExtension ext: String) -> URL? {
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
                return url
            }
        }
        return nil
    }
}
enum PaperInstrumentKind: String, CaseIterable {
    case piano
    case guitar
    case drums

    var assetName: String {
        switch self {
        case .piano: return "piano-line"
        case .guitar: return "guitar-line"
        case .drums: return "drums-line"
        }
    }

    var title: String {
        switch self {
        case .piano: return "钢琴"
        case .guitar: return "电吉他"
        case .drums: return "九鼓"
        }
    }

    var subtitle: String {
        switch self {
        case .piano: return "C4–C5 · 白键九枚"
        case .guitar: return "六弦 · 品位 0–12"
        case .drums: return "九宫格 · 独立反馈"
        }
    }
}

struct PaperInstrumentArt: View {
    let kind: PaperInstrumentKind
    var contentMode: ContentMode = .fit

    var body: some View {
        Group {
            if let image = PaperOrbitMedia.image(named: kind.assetName) {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }
}

struct PaperReferencePrint: View {
    var body: some View {
        Group {
            if let image = PaperOrbitMedia.image(named: "paper-orbit-reference") {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .accessibilityLabel("灰白纸张、铅笔轨道与手绘线团参考画片")
    }
}

struct PaperGrain: View {
    var opacity: Double = 0.20

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 3
            var index: Int = 0
            while y < size.height {
                let drift: CGFloat = CGFloat((index * 37) % 19) - 9
                var path = Path()
                path.move(to: CGPoint(x: -12, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width + 12, y: y + drift * 0.18),
                    control1: CGPoint(x: size.width * 0.32, y: y + drift),
                    control2: CGPoint(x: size.width * 0.68, y: y - drift)
                )
                context.stroke(
                    path,
                    with: .color(PaperPalette.pencil.opacity(index % 5 == 0 ? 0.18 : 0.07)),
                    lineWidth: 0.45
                )
                y += 5.5
                index += 1
            }
            for index in 0..<42 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 131) % 991) / 991 * size.height
                let rect = CGRect(x: x, y: y, width: index % 7 == 0 ? 2 : 1, height: 1)
                context.fill(Path(rect), with: .color(PaperPalette.pencil.opacity(0.17)))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PaperOrbitBackdrop: View {
    let scene: CosmicScene

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                PaperPalette.paper
                PaperGrain(opacity: 0.22)
                Canvas { context, canvasSize in
                    drawOrbits(context: &context, size: canvasSize)
                    drawMarks(context: &context, size: canvasSize)
                }
                .allowsHitTesting(false)
                LinearGradient(
                    colors: [.clear, PaperPalette.paperDeep.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.55)
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawOrbits(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.30)
        for index in 0..<4 {
            let radius = min(size.width, size.height) * (0.22 + CGFloat(index) * 0.105)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius * 0.42,
                width: radius * 2,
                height: radius * 0.84
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(PaperPalette.pencil.opacity(0.17 - Double(index) * 0.022)),
                lineWidth: 0.8
            )
        }

        let dots: [(CGFloat, CGFloat, Color, CGFloat)] = [
            (0.12, 0.32, PaperPalette.green, 13),
            (0.30, 0.57, PaperPalette.blue, 13),
            (0.91, 0.19, PaperPalette.red, 13),
            (0.72, 0.78, PaperPalette.pencil, 9)
        ]
        for (x, y, color, diameter) in dots {
            let rect = CGRect(
                x: size.width * x - diameter / 2,
                y: size.height * y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.62)))
        }

        var scribble = Path()
        let core = CGPoint(x: size.width * 0.70, y: size.height * 0.62)
        for index in 0..<18 {
            let angle = Double(index) * .pi * 2 / 18
            let radius = CGFloat(31 + (index % 3) * 7)
            let point = CGPoint(
                x: core.x + CGFloat(cos(angle)) * radius,
                y: core.y + CGFloat(sin(angle)) * radius * 0.82
            )
            if index == 0 {
                scribble.move(to: point)
            } else {
                scribble.addLine(to: point)
            }
        }
        scribble.closeSubpath()
        context.stroke(
            scribble,
            with: .color(PaperPalette.red.opacity(0.22)),
            lineWidth: 0.8
        )
    }

    private func drawMarks(context: inout GraphicsContext, size: CGSize) {
        for index in 0..<30 {
            let x = CGFloat((index * 59) % 983) / 983 * size.width
            let y = CGFloat((index * 113) % 971) / 971 * size.height
            let length = CGFloat(2 + (index % 4) * 2)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + length, y: y - length * 0.35))
            context.stroke(
                path,
                with: .color(index % 6 == 0 ? PaperPalette.red.opacity(0.26) : PaperPalette.pencil.opacity(0.35)),
                lineWidth: 0.7
            )
        }
    }
}

struct PaperOrbitMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(PaperPalette.pencil.opacity(0.9), lineWidth: 0.8)
                .frame(width: size * 0.94, height: size * 0.42)
                .rotationEffect(.degrees(-20))
            Ellipse()
                .stroke(PaperPalette.pencil.opacity(0.55), lineWidth: 0.7)
                .frame(width: size * 0.70, height: size * 0.28)
                .rotationEffect(.degrees(17))
            Circle()
                .fill(PaperPalette.red.opacity(0.82))
                .frame(width: size * 0.20, height: size * 0.20)
            Circle()
                .fill(PaperPalette.paper)
                .frame(width: size * 0.09, height: size * 0.09)
            Circle()
                .fill(PaperPalette.green)
                .frame(width: size * 0.075, height: size * 0.075)
                .offset(x: size * 0.38, y: -size * 0.12)
            Circle()
                .fill(PaperPalette.blue)
                .frame(width: size * 0.055, height: size * 0.055)
                .offset(x: -size * 0.24, y: size * 0.17)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PaperSectionLabel: View {
    let index: String
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Text(index)
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(PaperPalette.red)
            Rectangle()
                .fill(PaperPalette.pencil.opacity(0.5))
                .frame(width: 24, height: 0.8)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .tracking(0.8)
                .foregroundStyle(PaperPalette.inkSoft)
        }
    }
}

struct PaperTag: View {
    let text: String
    var color: Color = PaperPalette.inkSoft

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .serif))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
            )
    }
}

struct PaperCardSurface: ViewModifier {
    var fill: Color = PaperPalette.paperWhite

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.45), radius: 8, y: 3)
    }
}

extension View {
    func paperCard(fill: Color = PaperPalette.paperWhite) -> some View {
        modifier(PaperCardSurface(fill: fill))
    }
}

struct PaperRecordView<Label: View>: View {
    let isPlaying: Bool
    let label: Label

    init(isPlaying: Bool, @ViewBuilder label: () -> Label) {
        self.isPlaying = isPlaying
        self.label = label()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying ? 1.0 / 20.0 : 1.0)) { timeline in
            let turn = isPlaying
                ? timeline.date.timeIntervalSinceReferenceDate * 7
                : -10.0
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.94, blue: 0.91),
                                    Color(red: 0.78, green: 0.76, blue: 0.72)
                                ],
                                center: .topLeading,
                                startRadius: 4,
                                endRadius: diameter
                            )
                        )
                        .shadow(color: PaperPalette.shadow.opacity(0.55), radius: 18, y: 9)

                    ForEach(0..<26, id: \.self) { index in
                        Circle()
                            .stroke(
                                PaperPalette.ink.opacity(index % 4 == 0 ? 0.16 : 0.08),
                                lineWidth: 0.45
                            )
                            .padding(diameter * (0.045 + CGFloat(index) * 0.012))
                    }

                    Circle()
                        .strokeBorder(PaperPalette.paperWhite.opacity(0.8), lineWidth: 1)
                        .padding(diameter * 0.025)

                    AngularGradient(
                        colors: [
                            .clear,
                            PaperPalette.paperWhite.opacity(0.34),
                            .clear,
                            .clear
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    )
                    .clipShape(Circle())
                    .padding(diameter * 0.035)

                    label
                        .clipShape(Circle())
                        .padding(diameter * 0.29)
                        .overlay(
                            Circle()
                                .stroke(PaperPalette.ink.opacity(0.30), lineWidth: 0.8)
                                .padding(diameter * 0.29)
                        )

                    Circle()
                        .fill(PaperPalette.paper)
                        .frame(width: diameter * 0.032, height: diameter * 0.032)
                        .overlay(Circle().stroke(PaperPalette.ink.opacity(0.45), lineWidth: 0.7))
                }
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 360)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    tonearm(diameter: diameter)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityLabel(isPlaying ? "唱片正在旋转" : "唱片待机")
    }

    private func tonearm(diameter: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(PaperPalette.red.opacity(0.75))
                .frame(width: diameter * 0.055, height: diameter * 0.055)
                .overlay(Circle().stroke(PaperPalette.ink.opacity(0.35), lineWidth: 0.7))
            Capsule()
                .fill(PaperPalette.pencil.opacity(0.85))
                .frame(width: 3, height: diameter * 0.24)
                .offset(x: diameter * 0.022, y: diameter * 0.028)
            Circle()
                .fill(PaperPalette.paper)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(PaperPalette.ink.opacity(0.4), lineWidth: 0.8))
                .offset(x: diameter * 0.016, y: diameter * 0.225)
        }
        .rotationEffect(.degrees(24))
        .offset(x: -diameter * 0.03, y: diameter * 0.015)
        .allowsHitTesting(false)
    }
}
