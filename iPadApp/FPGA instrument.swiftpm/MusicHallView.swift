import SwiftUI

struct MusicHallView: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    @EnvironmentObject private var bluetooth: InstrumentBluetooth
    let onBackHome: () -> Void

    @State private var openedSongID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let openedSongID, let song = library.songs.first(where: { $0.id == openedSongID }) {
                MusicHallPlayerView(
                    library: library,
                    controller: controller,
                    song: song,
                    onBackToLibrary: { self.openedSongID = nil },
                    onUnavailable: { self.openedSongID = nil }
                )
            } else {
                MusicHallLibraryView(
                    library: library,
                    controller: controller,
                    onOpen: { song in
                        guard song.isCached else { return }
                        if controller.hasSession, controller.activePack?.id != song.id {
                            controller.stop {
                                openedSongID = song.id
                            }
                        } else {
                            openedSongID = song.id
                        }
                    },
                    onBackHome: leaveHome
                )
            }
        }
        .background(
            CosmicBackdrop(scene: openedSongID == nil ? .library : .musicHall)
                .ignoresSafeArea()
        )
        .onAppear {
            library.refreshCatalog()
        }
        .onDisappear {
            controller.handleBackground()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: leaveHome) {
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

            Text("音乐厅")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(PixelPalette.ink)

            CosmicTag(text: "曲库 + 播放页", color: CosmicPalette.amber)

            Spacer(minLength: 8)
            Text(bluetooth.isPerformanceSinkAvailable ? "FPGA 设备可见" : "BLE 未就绪")
                .font(.system(size: 10, weight: .bold, design: .serif))
                .foregroundStyle(bluetooth.isPerformanceSinkAvailable ? PixelPalette.good : PixelPalette.muted)
            Text(AppInfo.versionLabel)
                .font(.system(size: 10, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(PixelPanelShape(cut: 4).fill(PixelPalette.card))
                .overlay(PixelPanelShape(cut: 4).stroke(PixelPalette.line, lineWidth: 0.8))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(CosmicPalette.night.opacity(0.62))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CosmicPalette.lineWarm)
                .frame(height: 0.8)
        }
    }

    private func leaveHome() {
        onBackHome()
    }
}

struct MusicHallMiniPlayer: View {
    @ObservedObject var controller: MusicHallController
    let onOpen: () -> Void

    var body: some View {
        if let pack = controller.activePack, controller.hasSession {
            HStack(spacing: 10) {
                MusicHallCoverView(pack: pack, catalog: nil, title: pack.title, compact: true)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title)
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                        .lineLimit(1)
                    Text("\(controller.presentationLabel) · \(musicHallDurationText(controller.displayTime()))")
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                }
                Spacer(minLength: 0)
                Button("打开播放页", action: onOpen)
                    .buttonStyle(
                        PixelOutlineButtonStyle(
                            fontSize: 10,
                            horizontalPadding: 9,
                            verticalPadding: 5
                        )
                    )
                Button("停止") {
                    controller.stop()
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 10,
                        horizontalPadding: 9,
                        verticalPadding: 5,
                        foreground: PixelPalette.miss,
                        border: PixelPalette.miss.opacity(0.45)
                    )
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PixelPalette.secondary)
            .overlay(alignment: .top) {
                Rectangle().fill(PixelPalette.line).frame(height: 1)
            }
        }
    }
}
