import SwiftUI
import SpriteKit
import Foundation

struct PianoPracticeView: View {
    @ObservedObject var session: PianoPracticeSession
    @ObservedObject var audio: PianoSoundEngine
    let onBackHome: () -> Void
    @EnvironmentObject private var performance: PracticePerformanceController
    @EnvironmentObject private var freePlayRouter: FreePlayEventRouter
    @EnvironmentObject private var bluetooth: InstrumentBluetooth
    @State private var pageToken: UUID?

    var body: some View {
        VStack(spacing: 10) {
            topBar
            PixelScoreBar(session: session)
            board
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onAppear {
            performance.attach(router: freePlayRouter, bluetooth: bluetooth)
            session.attachPerformance(performance)
            pageToken = performance.beginPage(
                .piano,
                prepareLocal: { audio.prepare() },
                stopLocal: { audio.stopAll() }
            )
            session.performancePageToken = pageToken
        }
        .onDisappear {
            session.cancelPerformanceInput()
            if let pageToken {
                performance.endPage(token: pageToken, reason: .leavePage)
            }
            if let endedToken = pageToken,
               session.performancePageToken == endedToken {
                session.attachPerformance(nil)
                session.performancePageToken = nil
            }
            pageToken = nil
        }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("钢琴入门 · 八白键")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        PixelPhaseTag(phase: session.phase)
                    }

                    Text("90 BPM · C4–C5 · 短音/长按谱面约 30 秒")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                }

                Spacer(minLength: 4)

                PixelAudioChip(
                    title: audio.statusTitle,
                    icon: audioStatusIcon,
                    tint: audioTint
                )
            }

            HStack(spacing: 8) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primaryIcon)
                }
                .buttonStyle(
                    PixelFilledButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 15,
                        verticalPadding: 9
                    )
                )

                Button(action: { session.start() }) {
                    Label("重新开始", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 13,
                        verticalPadding: 9
                    )
                )
                .disabled(session.phase == .idle)
                .opacity(session.phase == .idle ? 0.45 : 1)

                Spacer(minLength: 4)

                Text("键位 A S D F G H J K · 长按：按住头，尾到再松 · 音源可选 FPGA")
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 5) {
                Image(systemName: audioStatusIcon)
                Text(audioLineText)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .medium, design: .serif))
            .foregroundStyle(audioTint)

            HStack(spacing: 5) {
                PracticeSourceControl(kind: .piano)
                Button(session.reduceMotion ? "标准动效" : "降低动效") {
                    session.reduceMotion.toggle()
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 9,
                        horizontalPadding: 8,
                        verticalPadding: 5
                    )
                )
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
            .background(PixelPalette.background)

            overlayContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(PixelPanelShape(cut: 12))
        .overlay(
            PixelPanelShape(cut: 12)
                .stroke(PixelPalette.line, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .background {
            ZStack {
                PixelPanelShape(cut: 12)
                    .fill(PixelPalette.shadow)
                    .offset(y: 3)
                PixelPanelShape(cut: 12)
                    .fill(PixelPalette.card)
            }
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch session.phase {
        case .idle:
            PianoIdleOverlay(
                audioDetail: audioLineText,
                audioIcon: audioStatusIcon,
                audioTint: audioTint,
                onStart: { session.start() }
            )
        case .paused:
            PixelPauseOverlay(session: session)
        case .finished:
            PixelResultOverlay(
                session: session,
                subtitle: resultSubtitle,
                onBackHome: onBackHome
            )
        default:
            EmptyView()
        }
    }

    private var audioStatusIcon: String {
        switch audio.status {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "speaker.slash.fill"
        case .unprepared, .preparing:
            return "waveform"
        }
    }

    private var audioTint: Color {
        switch audio.status {
        case .ready:
            return PixelPalette.good
        case .unavailable:
            return PixelPalette.miss
        case .unprepared, .preparing:
            return PixelPalette.muted
        }
    }

    private var audioLineText: String {
        if freePlayRouter.isHardwareMode {
            return "FPGA音箱：真实触键经根级 BLE 队列发送；本地音色关闭。"
        }
        switch audio.status {
        case .ready:
            return audio.statusDetail
        case .unavailable(let reason):
            return "\(reason)。视觉练习仍可完成。"
        case .unprepared, .preparing:
            return audio.statusDetail
        }
    }

    private var resultSubtitle: String {
        if freePlayRouter.isHardwareMode {
            return "FPGA音箱 · 真实触键发声；判定与动画由音游处理"
        }
        if audio.isReady {
            return "iPad本地声音 · 真实触键发声；判定与动画由音游处理"
        }
        return "无声演示 · 判定与动画由音游处理"
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

struct PixelPhaseTag: View {
    let phase: PracticePhase

    var body: some View {
        PixelTag(
            text: text,
            foreground: color,
            fill: PixelPalette.secondary,
            border: PixelPalette.line
        )
    }

    private var text: String {
        switch phase {
        case .idle: return "待开始"
        case .countdown: return "倒计时"
        case .playing: return "进行中"
        case .paused: return "已暂停"
        case .finished: return "已结束"
        }
    }

    private var color: Color {
        switch phase {
        case .idle: return PixelPalette.muted
        case .countdown: return PixelPalette.accentDark
        case .playing: return PixelPalette.good
        case .paused: return PixelPalette.accentDark
        case .finished: return PixelPalette.muted
        }
    }
}

struct PixelAudioChip: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .bold, design: .serif))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(PixelPanelShape(cut: 4).fill(PixelPalette.card))
        .overlay(
            PixelPanelShape(cut: 4)
                .stroke(tint.opacity(0.40), lineWidth: 1)
        )
    }
}

struct PixelScoreBar: View {
    @ObservedObject var session: PracticeSession

    var body: some View {
        HStack(spacing: 8) {
            PianoScoreTile(
                title: "分数",
                value: session.stats.score,
                tint: PixelPalette.ink,
                bounces: false
            )
            PianoScoreTile(
                title: "当前连击",
                value: session.stats.combo,
                tint: PixelPalette.accentDark,
                bounces: true
            )
            PianoScoreTile(
                title: "最大连击",
                value: session.stats.maxCombo,
                tint: PixelPalette.ink,
                bounces: false
            )
            PianoProgressTile(
                resolved: session.resolvedCount,
                total: session.totalNotes,
                progress: session.progress
            )
        }
    }
}

private struct PianoScoreTile: View {
    let title: String
    let value: Int
    let tint: Color
    let bounces: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)

            if bounces {
                BouncyNumberText(value: value, tint: tint)
            } else {
                Text("\(value)")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(PixelPanelShape(cut: 5).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 5).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private struct PianoProgressTile: View {
    let resolved: Int
    let total: Int
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("进度")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                Spacer(minLength: 2)
                Text("\(resolved)/\(total)")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(PixelPalette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(PixelPanelShape(cut: 5).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 5).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private struct PianoIdleOverlay: View {
    let audioDetail: String
    let audioIcon: String
    let audioTint: Color
    let onStart: () -> Void

    var body: some View {
        ZStack {
            PixelPalette.background.opacity(0.84)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    PixelFeatureIcon(kind: .piano, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("钢琴音游")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text("C4–C5 八白键 · 90 BPM 入门谱面")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    Spacer(minLength: 0)
                }

                Text("按下白键触发反馈与判定。音符提前 2 秒出现，后段包含三音和弦。")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PianoKeyHintRow()

                HStack(spacing: 5) {
                    Image(systemName: audioIcon)
                    Text(audioDetail)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundStyle(audioTint)

                Button(action: onStart) {
                    Label("开始练习", systemImage: "play.fill")
                }
                .buttonStyle(
                    PixelFilledButtonStyle(
                        fontSize: 14,
                        horizontalPadding: 18,
                        verticalPadding: 10
                    )
                )
                .padding(.top, 2)

                Text("Perfect ±80 ms · Good ±160 ms · 长按尾 -120/+220 ms · 提前松手断连")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(PixelPalette.line, lineWidth: 1.5)
            )
            .padding(16)
        }
    }
}

private struct PianoKeyHintRow: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(PianoKey.allCases) { key in
                VStack(spacing: 1) {
                    Text(key.keyboardLetter)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    Text(key.name)
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(PixelPanelShape(cut: 3).fill(PixelPalette.secondary))
                .overlay(
                    PixelPanelShape(cut: 3)
                        .stroke(PixelPalette.line, lineWidth: 1)
                )
            }
        }
    }
}

struct PixelPauseOverlay: View {
    let session: PracticeSession

    var body: some View {
        ZStack {
            PixelPalette.background.opacity(0.82)

            VStack(spacing: 12) {
                Text("已暂停")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)

                Text("练习时间已冻结。继续后从当前位置恢复，不会跳跃。")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: { session.resume() }) {
                        Label("继续", systemImage: "play.fill")
                    }
                    .buttonStyle(PixelFilledButtonStyle())

                    Button(action: { session.start() }) {
                        Label("重新开始", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PixelOutlineButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 450)
            .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(PixelPalette.line, lineWidth: 1.5)
            )
            .padding(16)
        }
    }
}

struct PixelResultOverlay: View {
    @ObservedObject var session: PracticeSession
    let subtitle: String
    let onBackHome: () -> Void

    var body: some View {
        ZStack {
            PixelPalette.background.opacity(0.86)

            VStack(spacing: 11) {
                titleRow
                subtitleText
                scoreRow
                pillsRow
                metricsRow
                checkRow
                buttonsRow
            }
            .padding(21)
            .frame(maxWidth: 530)
            .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(PixelPalette.line, lineWidth: 1.5)
            )
            .padding(16)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PixelPalette.good)
            Text("练习结束")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
        }
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.system(size: 11, weight: .medium, design: .serif))
            .foregroundStyle(PixelPalette.muted)
    }

    private var scoreRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(session.stats.score)")
                .font(.system(size: 44, weight: .heavy, design: .serif))
                .monospacedDigit()
                .foregroundStyle(PixelPalette.ink)
            Text("总分")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
        }
    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            PianoResultPill(title: "Perfect", count: session.stats.perfect, color: PixelPalette.accentDark)
            PianoResultPill(title: "Good", count: session.stats.good, color: PixelPalette.good)
            PianoResultPill(title: "Miss", count: session.stats.miss, color: PixelPalette.miss)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 28) {
            PianoResultMetric(title: "最大连击", value: "\(session.stats.maxCombo)")
            PianoResultMetric(title: "命中率", value: "\(accuracyPercent)%")
        }
    }

    private var checkRow: some View {
        HStack(spacing: 5) {
            Image(systemName: statsMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(
                "Perfect \(session.stats.perfect) + Good \(session.stats.good) + Miss \(session.stats.miss) = \(countedNotes) / \(session.totalNotes)"
            )
        }
        .font(.system(size: 10, weight: .medium, design: .serif))
        .foregroundStyle(statsMatch ? PixelPalette.good : PixelPalette.miss)
    }

    private var buttonsRow: some View {
        HStack(spacing: 10) {
            Button(action: { session.start() }) {
                Label("再练一次", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PixelFilledButtonStyle())

            Button(action: onBackHome) {
                Label("返回主页", systemImage: "house.fill")
            }
            .buttonStyle(PixelOutlineButtonStyle())
        }
        .padding(.top, 2)
    }

    private var countedNotes: Int {
        session.stats.perfect + session.stats.good + session.stats.miss
    }

    private var statsMatch: Bool {
        countedNotes == session.totalNotes
    }

    private var accuracyPercent: Int {
        Int((session.accuracy * 100).rounded())
    }
}

private struct PianoResultPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(PixelPalette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(PixelPanelShape(cut: 5).fill(color.opacity(0.10)))
        .overlay(
            PixelPanelShape(cut: 5)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
    }
}

private struct PianoResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(PixelPalette.ink)
        }
    }
}
