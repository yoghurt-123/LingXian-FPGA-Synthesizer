import AVFoundation
import SwiftUI
import UIKit

final class MusicHallAmbientVideoController: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var failed = false

    init() {
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false

        guard let url = PaperOrbitMedia.url(named: "orbit-motion-loop", withExtension: "mp4") else {
            failed = true
            return
        }

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func setActive(_ active: Bool) {
        guard !failed else { return }
        if active {
            player.playImmediately(atRate: 1)
        } else {
            player.pause()
        }
    }

    deinit {
        player.pause()
        looper?.disableLooping()
    }
}

struct MusicHallAmbientVideoStageView: View {
    @ObservedObject var controller: MusicHallController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var video = MusicHallAmbientVideoController()
    @State private var isVisible = false

    private let aspect: CGFloat = 960.0 / 544.0

    var body: some View {
        ZStack {
            PaperPalette.paperDeep

            if let still = PaperOrbitMedia.image(named: "orbit-motion-still") {
                still
                    .resizable()
                    .scaledToFit()
                    .opacity(0.94)
            }

            if !video.failed {
                PaperOrbitPlayerSurface(player: video.player)
                    .opacity(0.98)
            }

            LinearGradient(
                colors: [
                    PaperPalette.paper.opacity(0.04),
                    Color.clear,
                    PaperPalette.ink.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("乐曲进行中")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(PaperPalette.paperWhite)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(PaperPalette.ink.opacity(0.58))
                            )
                        Text("装饰循环 · 不代表歌曲进度")
                            .font(.system(size: 8, weight: .medium, design: .serif))
                            .foregroundStyle(PaperPalette.paperWhite.opacity(0.82))
                            .padding(.horizontal, 7)
                    }
                    Spacer(minLength: 0)
                    Text(modeText)
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(PaperPalette.paperWhite.opacity(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(PaperPalette.ink.opacity(0.52))
                        )
                }
                .padding(.horizontal, 12)
                .padding(.top, 9)

                Spacer(minLength: 8)

                HStack(spacing: 7) {
                    ForEach(MusicHallInstrument.allCases) { instrument in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(instrument.tint.opacity(controller.phase == .playing ? 0.95 : 0.48))
                                .frame(width: 5, height: 5)
                            Text(instrument.title)
                                .font(.system(size: 8, weight: .medium, design: .serif))
                                .foregroundStyle(PaperPalette.paperWhite.opacity(0.92))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(PaperPalette.ink.opacity(0.46)))
                    }
                    Spacer(minLength: 0)
                    Text("静音装饰")
                        .font(.system(size: 7, weight: .medium, design: .serif))
                        .foregroundStyle(PaperPalette.paperWhite.opacity(0.68))
                        .padding(.trailing, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("乐曲进行中的静音装饰视频")
        .onAppear {
            isVisible = true
            updateVideoPlayback()
        }
        .onDisappear {
            isVisible = false
            video.setActive(false)
        }
        .onChange(of: scenePhase) { _, _ in
            updateVideoPlayback()
        }
    }

    private var modeText: String {
        if controller.stopUnconfirmed { return "停止未确认" }
        switch controller.mode {
        case .none:
            return "舞台待机"
        case .stagePreview:
            return "静音舞台预览"
        case .fpga:
            if controller.phase == .starting { return "等待 ESP PLAY 状态" }
            if controller.playbackClockIsEstimated { return "ESP 播放流 · FPGA 无进度" }
            return "ESP 播放中 · FPGA 无进度"
        }
    }

    private func updateVideoPlayback() {
        video.setActive(isVisible && scenePhase == .active)
    }
}

private struct PaperOrbitPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension MusicHallInstrument {
    var tint: Color {
        switch self {
        case .piano: return PaperPalette.red
        case .guitar: return PaperPalette.blue
        case .drums: return PaperPalette.green
        }
    }
}
