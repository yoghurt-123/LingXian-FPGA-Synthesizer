import SwiftUI

struct PracticeSpeedControl: View {
    let speed: Double
    let onChange: (Double) -> Void

    private let options: [Double] = [0.75, 1.0]

    var body: some View {
        HStack(spacing: 3) {
            Text("速度")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            ForEach(options, id: \.self) { option in
                Button {
                    onChange(option)
                } label: {
                    Text(option < 1 ? "慢 0.75×" : "标准 1.0×")
                        .font(.system(size: 8, weight: .heavy, design: .serif))
                        .foregroundStyle(abs(speed - option) < 0.001 ? PixelPalette.card : PixelPalette.ink)
                        .padding(.horizontal, 5)
                        .frame(height: 24)
                        .background(abs(speed - option) < 0.001 ? PixelPalette.accentDark : PixelPalette.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(PixelPanelShape(cut: 4).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 4).stroke(PixelPalette.line, lineWidth: 0.8))
    }
}
