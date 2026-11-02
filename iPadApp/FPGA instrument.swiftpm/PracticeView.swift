import SwiftUI
import SpriteKit

struct PracticeView: View {
    @ObservedObject var session: PracticeSession
    let onBackHome: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            topBar
            PracticeStatusBar(session: session)
            board
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(session.chart.title)
                            .font(.title3.bold())
                        PracticePhaseBadge(phase: session.phase)
                    }

                    Text("\(session.chart.bpm) BPM · 音符谱面\(session.chart.durationText)（不含倒计时） · 内置固定谱面")
                        .font(.caption)
                        .foregroundStyle(PaperPalette.ink.opacity(0.58))
                }

                Spacer(minLength: 4)

                Label("触屏演示模式", systemImage: "hand.tap.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PaperPalette.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(PaperPalette.red.opacity(0.13)))
                    .overlay(Capsule().stroke(PaperPalette.red.opacity(0.34), lineWidth: 1))
            }

            HStack(spacing: 8) {
                PracticeFilledButton(
                    title: primaryTitle,
                    systemImage: primaryIcon,
                    tint: primaryColor,
                    action: primaryAction
                )

                PracticeOutlineButton(
                    title: "重新开始",
                    systemImage: "arrow.counterclockwise",
                    action: { session.start() }
                )
                .disabled(session.phase == .idle)
                .opacity(session.phase == .idle ? 0.45 : 1)

                Spacer(minLength: 4)

                Label("本轮为无伴奏节奏测试", systemImage: "music.note")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PaperPalette.ink.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var board: some View {
        ZStack {
            SpriteView(
                scene: session.scene,
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
            .background(PaperPalette.paperDeep)

            overlayContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PaperPalette.ink.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch session.phase {
        case .idle:
            idleOverlay
        case .paused:
            PracticePausedOverlay(session: session)
        case .finished:
            PracticeResultOverlay(
                session: session,
                subtitle: "触屏演示模式 · 无伴奏鼓练习",
                onBackHome: onBackHome
            )
        default:
            EmptyView()
        }
    }

    private var idleOverlay: some View {
        ZStack {
            PaperPalette.ink.opacity(0.18)

            VStack(spacing: 12) {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(PaperPalette.red)

                Text("四轨节奏练习")
                    .font(.title2.bold())

                Text("点击开始，先进行 3·2·1 倒计时。音符会提前 2 秒出现。")
                    .font(.subheadline)
                    .foregroundStyle(PaperPalette.ink.opacity(0.72))
                    .multilineTextAlignment(.center)

                Text("在底部四个击打区按下手指；双押需要两根手指同时触屏。")
                    .font(.caption)
                    .foregroundStyle(PaperPalette.ink.opacity(0.54))
                    .multilineTextAlignment(.center)

                PracticeFilledButton(
                    title: "开始练习",
                    systemImage: "play.fill",
                    tint: PaperPalette.red,
                    action: { session.start() }
                )
                .padding(.top, 2)

                Text("Perfect ±80 ms · Good ±160 ms · 触屏演示 · 无伴奏")
                    .font(.caption2)
                    .foregroundStyle(PaperPalette.ink.opacity(0.46))
            }
            .padding(22)
            .frame(maxWidth: 470)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PaperPalette.ink.opacity(0.10), lineWidth: 1)
            )
            .padding(20)
        }
    }

    private var primaryTitle: String {
        switch session.phase {
        case .idle: return "开始"
        case .countdown, .playing: return "暂停"
        case .paused: return "继续"
        case .finished: return "再练一次"
        }
    }

    private var primaryIcon: String {
        switch session.phase {
        case .idle: return "play.fill"
        case .countdown, .playing: return "pause.fill"
        case .paused: return "play.fill"
        case .finished: return "arrow.clockwise"
        }
    }

    private var primaryColor: Color {
        switch session.phase {
        case .paused: return PaperPalette.green
        case .countdown, .playing: return PaperPalette.red
        default: return PaperPalette.red
        }
    }

    private func primaryAction() {
        switch session.phase {
        case .idle, .finished:
            session.start()
        case .countdown, .playing:
            session.pause()
        case .paused:
            session.resume()
        }
    }
}
