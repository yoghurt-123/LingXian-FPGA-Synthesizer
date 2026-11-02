import SwiftUI
import UIKit

enum PixelPalette {
    static let backgroundUI: UIColor = makeColor(241, 240, 236)
    static let cardUI: UIColor = makeColor(248, 247, 243)
    static let secondaryUI: UIColor = makeColor(232, 230, 223)
    static let accentUI: UIColor = makeColor(168, 91, 85)
    static let accentDarkUI: UIColor = makeColor(139, 70, 65)
    static let inkUI: UIColor = makeColor(54, 54, 50)
    static let mutedUI: UIColor = makeColor(122, 119, 111)
    static let lineUI: UIColor = makeColor(201, 198, 190)
    static let goodUI: UIColor = makeColor(80, 115, 101)
    static let missUI: UIColor = makeColor(168, 91, 85)
    static let shadowUI: UIColor = UIColor(red: 0.18, green: 0.17, blue: 0.14, alpha: 0.10)

    static let background: Color = PaperPalette.paper
    static let card: Color = PaperPalette.paperWhite
    static let secondary: Color = PaperPalette.paperDeep
    static let accent: Color = PaperPalette.red
    static let accentDark: Color = PaperPalette.redDeep
    static let ink: Color = PaperPalette.ink
    static let muted: Color = PaperPalette.inkSoft
    static let line: Color = PaperPalette.line
    static let good: Color = PaperPalette.green
    static let miss: Color = PaperPalette.red
    static let shadow: Color = PaperPalette.shadow

    private static func makeColor(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1.0) -> UIColor {
        let r: CGFloat = CGFloat(red) / 255.0
        let g: CGFloat = CGFloat(green) / 255.0
        let b: CGFloat = CGFloat(blue) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }
}

struct PixelPanelShape: Shape {
    var cut: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let radius = min(max(cut, 4), min(rect.width, rect.height) / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

struct PixelPanelBackground: View {
    var fill: Color = PixelPalette.card
    var cut: CGFloat = 8

    var body: some View {
        ZStack {
            PixelPanelShape(cut: cut)
                .fill(PaperPalette.shadow.opacity(0.34))
                .offset(y: 2)
            PixelPanelShape(cut: cut)
                .fill(fill.opacity(0.92))
        }
    }
}

struct PixelTag: View {
    let text: String
    var foreground: Color = PixelPalette.ink
    var fill: Color = PixelPalette.card
    var border: Color = PixelPalette.line

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .serif))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PixelPanelShape(cut: 4).fill(fill.opacity(0.78)))
            .overlay(PixelPanelShape(cut: 4).stroke(border.opacity(0.8), lineWidth: 0.8))
    }
}

struct PixelFilledButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 14
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 10
    var fill: Color = PixelPalette.ink
    var foreground: Color = PixelPalette.background
    var border: Color = PixelPalette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .serif))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(PixelPanelBackground(fill: fill, cut: 8))
            .overlay(PixelPanelShape(cut: 8).stroke(border.opacity(0.9), lineWidth: 0.9))
            .shadow(color: PaperPalette.shadow.opacity(configuration.isPressed ? 0.08 : 0.36), radius: 5, y: 2)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct PixelOutlineButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 14
    var horizontalPadding: CGFloat = 15
    var verticalPadding: CGFloat = 9
    var foreground: Color = PixelPalette.ink
    var fill: Color = PixelPalette.card
    var border: Color = PixelPalette.line

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium, design: .serif))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(PixelPanelBackground(fill: fill, cut: 8))
            .overlay(PixelPanelShape(cut: 8).stroke(border.opacity(0.9), lineWidth: 0.9))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct PixelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                PixelPanelBackground(
                    fill: configuration.isPressed ? PixelPalette.secondary : PixelPalette.card,
                    cut: 10
                )
            )
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(
                        configuration.isPressed ? PixelPalette.accent : PixelPalette.line,
                        lineWidth: 0.8
                    )
            )
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct PixelDotPattern: View {
    var spacing: CGFloat = 18
    var dotSize: CGFloat = 2

    var body: some View {
        PaperGrain(opacity: 0.12)
    }
}

enum PixelFeatureIconKind {
    case note
    case grid
    case guitar
    case concert
    case drum
    case piano
    case book

    var instrument: PaperInstrumentKind? {
        switch self {
        case .guitar: return .guitar
        case .drum: return .drums
        case .piano: return .piano
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .note: return "music.note"
        case .grid: return "square.grid.2x2"
        case .concert: return "sparkles"
        case .book: return "book.closed"
        case .guitar, .drum, .piano: return "music.note"
        }
    }
}

struct PixelFeatureIcon: View {
    let kind: PixelFeatureIconKind
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            PixelPanelShape(cut: 10)
                .fill(PaperPalette.paperWhite.opacity(0.72))
            if let instrument = kind.instrument {
                PaperInstrumentArt(kind: instrument)
                    .padding(size * 0.11)
            } else {
                Image(systemName: kind.symbolName)
                    .font(.system(size: size * 0.38, weight: .light, design: .serif))
                    .foregroundStyle(PaperPalette.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            PixelPanelShape(cut: 10)
                .stroke(PaperPalette.line.opacity(0.85), lineWidth: 0.8)
        )
        .accessibilityHidden(true)
    }
}
