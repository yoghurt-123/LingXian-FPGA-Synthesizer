import SwiftUI
import SpriteKit
import Foundation

struct GuitarPracticeView: View {
    @ObservedObject var session: GuitarPracticeSession
    @ObservedObject var audio: GuitarSoundEngine
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
                .guitar,
                prepareLocal: { audio.prepare() },
                stopLocal: { audio.stopAll() },
                guitarState: {
                    PracticeGuitarState(fret: session.selectedFret, chordID: session.selectedChordID)
                }
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
                        Text("电吉他慢速教学 · 左右手")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        PixelPhaseTag(phase: session.phase)
                    }

                    Text("72 BPM · 20 音 · 空弦/2品/末尾和弦 · 换品前有空白准备")
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

                Text("左手先选并保持 · 真实触弦发声 · 音源可选 FPGA")
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
                PracticeSourceControl(kind: .guitar)
                PracticeSpeedControl(speed: session.speed) { value in
                    session.speed = value
                }
            }
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            let leftWidth: CGFloat = min(380, max(280, proxy.size.width * 0.36))
            HStack(spacing: 9) {
                GuitarLeftHandPanel(session: session)
                    .frame(width: leftWidth)
                sceneBoard
            }
        }
        .layoutPriority(1)
    }

    private var sceneBoard: some View {
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
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch session.phase {
        case .idle:
            GuitarIdleOverlay(
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
            return "FPGA音箱：真实触弦/触鼓经根级 BLE 队列发送；本地音色关闭。"
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
            return "FPGA音箱 · 真实触弦发声；判定与动画由音游处理"
        }
        if audio.isReady {
            return "iPad本地声音 · 真实触弦发声；判定与动画由音游处理"
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

private struct GuitarIdleOverlay: View {
    let audioDetail: String
    let audioIcon: String
    let audioTint: Color
    let onStart: () -> Void

    var body: some View {
        ZStack {
            PixelPalette.background.opacity(0.84)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    PixelFeatureIcon(kind: .guitar, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("电吉他音游 · 左右手")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text("空弦/2品为主 · 慢速可选 · 72 BPM")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    Spacer(minLength: 0)
                }

                Text("默认谱面以空弦和同一品位为主，换品只安排在乐句之间；末尾 4 个音使用 C/G/Dm/Am 和弦。左手手动选品或和弦，不自动切换。右侧真实触弦发声，错品/错和弦按 Miss 处理。慢速练习会同时缩放谱面、判定和动画。")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("屏幕从上到下：Q 6弦 E2 → Y 1弦 E4 · 品位 0–12")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)

                GuitarStringLegend()

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

                Text("Perfect ±100 ms · Good ±200 ms · 空弦/2品为主 · 完整0–12品可展开 · 音源可选 FPGA")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 600)
            .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(PixelPalette.line, lineWidth: 1.5)
            )
            .padding(16)
        }
    }
}

private struct GuitarStringLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(GuitarString.displayOrder) { string in
                VStack(spacing: 1) {
                    Text(string.keyboardKey)
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                    Text("\(string.rawValue) \(string.openName)")
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
