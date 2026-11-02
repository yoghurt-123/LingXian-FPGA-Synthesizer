import SwiftUI
import Foundation
import CoreGraphics

enum CosmicScene {
    case home
    case performance
    case piano
    case guitar
    case drums
    case musicHall
    case library
    case help
    case bluetooth
    case concert

    var title: String {
        switch self {
        case .home: return "乐器手记"
        case .performance: return "自由演奏"
        case .piano: return "钢琴音游"
        case .guitar: return "电吉他音阶"
        case .drums: return "架子鼓音阶"
        case .musicHall: return "音乐厅"
        case .library: return "曲库"
        case .help: return "使用说明"
        case .bluetooth: return "蓝牙连接"
        case .concert: return "纸上舞台"
        }
    }

    var base: [Color] {
        [PaperPalette.paper, PaperPalette.paperDeep]
    }

    var glow: Color {
        switch self {
        case .home, .library, .help: return PaperPalette.red
        case .performance, .bluetooth: return PaperPalette.green
        case .piano, .concert: return PaperPalette.blue
        case .guitar, .drums: return PaperPalette.red
        case .musicHall: return PaperPalette.redDeep
        }
    }

    var secondaryGlow: Color {
        switch self {
        case .home, .library: return PaperPalette.blue
        case .performance, .bluetooth: return PaperPalette.green
        case .piano, .concert: return PaperPalette.blue
        case .guitar, .drums: return PaperPalette.red
        case .musicHall: return PaperPalette.green
        case .help: return PaperPalette.pencil
        }
    }
}

enum CosmicPalette {
    static let night = PaperPalette.paper
    static let charcoal = PaperPalette.paperDeep
    static let panel = PaperPalette.paperWhite
    static let panelRaised = PaperPalette.paperWhite
    static let ivory = PaperPalette.ink
    static let ivoryMuted = PaperPalette.inkSoft
    static let steel = PaperPalette.pencil
    static let amber = PaperPalette.red
    static let amberBright = PaperPalette.redDeep
    static let teal = PaperPalette.green
    static let coral = PaperPalette.red
    static let paper = PaperPalette.paperWhite
    static let paperInk = PaperPalette.ink
    static let line = PaperPalette.line.opacity(0.72)
    static let lineWarm = PaperPalette.red.opacity(0.24)
}

struct CosmicBackdrop: View {
    let scene: CosmicScene

    var body: some View {
        PaperOrbitBackdrop(scene: scene)
    }
}

struct CosmicOrbitMark: View {
    var size: CGFloat = 54

    var body: some View {
        PaperOrbitMark(size: size)
    }
}

struct CosmicSectionLabel: View {
    let index: String
    let title: String

    var body: some View {
        PaperSectionLabel(index: index, title: title)
    }
}

struct CosmicTag: View {
    let text: String
    var color: Color = PaperPalette.inkSoft

    var body: some View {
        PaperTag(text: text, color: color)
    }
}

struct CosmicArchiveStamp: View {
    let index: String

    var body: some View {
        Text("ARCHIVE / \(index)")
            .font(.system(size: 8, weight: .medium, design: .serif))
            .tracking(1.0)
            .foregroundStyle(PaperPalette.redDeep)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(PaperPalette.red.opacity(0.35), lineWidth: 0.7)
            )
            .rotationEffect(.degrees(-2))
    }
}

struct CosmicCardModifier: ViewModifier {
    var fill: Color = PaperPalette.paperWhite

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.45), radius: 10, y: 4)
    }
}

extension View {
    func cosmicCard(fill: Color = PaperPalette.paperWhite) -> some View {
        modifier(CosmicCardModifier(fill: fill))
    }
}

struct CosmicPaperCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.35), radius: 8, y: 3)
    }
}

extension View {
    func cosmicPaperCard() -> some View {
        modifier(CosmicPaperCardModifier())
    }
}

struct CosmicPrimaryButtonStyle: ButtonStyle {
    var tint: Color = PaperPalette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .foregroundStyle(PaperPalette.paperWhite)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.7), lineWidth: 0.8)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.45), radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct CosmicSecondaryButtonStyle: ButtonStyle {
    var tint: Color = PaperPalette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .serif))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(configuration.isPressed ? 0.7 : 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PaperPalette.line, lineWidth: 0.8)
            )
    }
}

struct CosmicVinylRecord<Label: View>: View {
    let isPlaying: Bool
    let label: Label

    init(isPlaying: Bool, @ViewBuilder label: () -> Label) {
        self.isPlaying = isPlaying
        self.label = label()
    }

    var body: some View {
        PaperRecordView(isPlaying: isPlaying) {
            label
        }
    }
}
