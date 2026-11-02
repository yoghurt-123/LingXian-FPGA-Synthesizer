import SwiftUI
import SpriteKit
import Foundation

struct DrumKitPracticeView: View {
    @ObservedObject var session: DrumKitPracticeSession
    @ObservedObject var audio: DrumKitSoundEngine
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
                .drums,
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
                        Text("架子鼓入门 · 九宫格")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        PixelPhaseTag(phase: session.phase)
                    }

                    Text("100 BPM · 46 音 · 约 26 秒 · 小键盘 1–9 / 轮廓提示")
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

                Text("九宫格 · 小键盘 1–9 · 真实触鼓发声 · 音源可选 FPGA")
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

            PracticeSourceControl(kind: .drums)
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
            DrumKitIdleOverlay(
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
            return "FPGA音箱 · 真实触鼓发声；判定与动画由音游处理"
        }
        if audio.isReady {
            return "iPad本地声音 · 真实触鼓发声；判定与动画由音游处理"
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

private struct DrumKitIdleOverlay: View {
    let audioDetail: String
    let audioIcon: String
    let audioTint: Color
    let onStart: () -> Void

    var body: some View {
        ZStack {
            PixelPalette.background.opacity(0.84)

            VStack(spacing: 9) {
                HStack(spacing: 10) {
                    PixelFeatureIcon(kind: .drum, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("九宫格架子鼓")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text("九格轮廓提示 · 100 BPM · 小键盘 1–9")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    Spacer(minLength: 0)
                }

                Text("九个格子对应九种鼓。轮廓提前变亮，收缩到格子边缘时点击/敲击；开镲和闭镲分别操作，闭镲会止住开镲余音。")
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                DrumKitLegend()

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

                Text("Perfect ±80 ms · Good ±160 ms · 真实触鼓发声 · 音源可选 FPGA")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: 620)
            .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
            .overlay(
                PixelPanelShape(cut: 10)
                    .stroke(PixelPalette.line, lineWidth: 1.5)
            )
            .padding(14)
        }
    }
}

private struct DrumKitLegend: View {
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(FPGAKeyMap.drumPads.sorted { $0.gridIndex < $1.gridIndex }, id: \.id) { pad in
                VStack(spacing: 0) {
                    Text(pad.instrument.displayName)
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                        .lineLimit(1)
                    Text("小键盘\(pad.keypadNumber)")
                        .font(.system(size: 7, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                        .lineLimit(1)
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(PixelPanelShape(cut: 3).fill(PixelPalette.secondary))
                    .overlay(
                        PixelPanelShape(cut: 3)
                            .stroke(PixelPalette.line, lineWidth: 1)
                    )
            }
        }
    }
}
