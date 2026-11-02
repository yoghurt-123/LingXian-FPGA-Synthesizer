import SwiftUI

struct SubpageScaffold<Content: View>: View {
    let title: String
    let legacyNotice: Bool
    let onBackHome: () -> Void
    let content: Content

    init(
        title: String,
        legacyNotice: Bool = false,
        onBackHome: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.legacyNotice = legacyNotice
        self.onBackHome = onBackHome
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(
                title: title,
                legacyNotice: legacyNotice,
                onBackHome: onBackHome
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PageChrome: View {
    let title: String
    let legacyNotice: Bool
    let onBackHome: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBackHome) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                    Text("返回主页")
                        .foregroundStyle(PixelPalette.ink)
                }
            }
            .buttonStyle(
                PixelOutlineButtonStyle(
                    fontSize: 12,
                    horizontalPadding: 10,
                    verticalPadding: 6,
                    border: PixelPalette.line
                )
            )

            CosmicOrbitMark(size: 22)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
                .lineLimit(1)

            if legacyNotice {
                PixelTag(
                    text: "旧版视觉",
                    foreground: PixelPalette.muted,
                    fill: PixelPalette.secondary,
                    border: PixelPalette.line
                )
            }

            Spacer(minLength: 8)

            PageStatusTag()
            VersionTag()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PaperPalette.paperWhite.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PaperPalette.line.opacity(0.85))
                .frame(height: 0.8)
        }
    }
}

private struct PageStatusTag: View {
    @EnvironmentObject private var bluetooth: InstrumentBluetooth
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(PixelPalette.good)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(PixelPanelShape(cut: 7).fill(PixelPalette.card.opacity(0.76)))
        .overlay(PixelPanelShape(cut: 7).stroke(PixelPalette.line, lineWidth: 0.8))
    }

    private var statusText: String {
        if bluetooth.isPerformanceSinkAvailable {
            return "FPGA音箱就绪"
        }
        if bluetooth.isReady {
            return "BLE 诊断连接 · 能力未确认"
        }
        return "iPad本地 · BLE 未连接"
    }
}

private struct VersionTag: View {
    var body: some View {
        Text(AppInfo.versionLabel)
            .font(.system(size: 11, weight: .bold, design: .serif))
            .foregroundStyle(PixelPalette.accentDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(PixelPanelShape(cut: 7).fill(PixelPalette.card.opacity(0.76)))
            .overlay(PixelPanelShape(cut: 7).stroke(PixelPalette.line, lineWidth: 0.8))
    }
}
