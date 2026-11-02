import SwiftUI
import UniformTypeIdentifiers

struct MusicHallLibraryView: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    let onOpen: (MusicHallSong) -> Void
    let onBackHome: () -> Void

    @State private var showCatalogConfig = false
    @State private var showImporter = false
    @State private var pendingDelete: MusicHallSong?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                catalogStrip
                if let first = library.onlineSongs.first {
                    MusicHallHeroCard(
                        library: library,
                        controller: controller,
                        song: first,
                        onOpen: onOpen
                    )
                }
                if !library.cachedSongs.isEmpty {
                    sectionTitle("已缓存到 iPad", detail: "离线包可打开播放页；不是“设备已缓存”")
                    LazyVStack(spacing: 9) {
                        ForEach(library.cachedSongs) { song in
                            MusicHallSongRow(
                                library: library,
                                controller: controller,
                                song: song,
                                onOpen: onOpen,
                                onDelete: { pendingDelete = song }
                            )
                        }
                    }
                }
                if !library.onlineSongs.isEmpty {
                    sectionTitle("在线曲目", detail: "下载进度与设备传输进度分开显示")
                    LazyVStack(spacing: 9) {
                        ForEach(library.onlineSongs) { song in
                            MusicHallSongRow(
                                library: library,
                                controller: controller,
                                song: song,
                                onOpen: onOpen,
                                onDelete: { pendingDelete = song }
                            )
                        }
                    }
                }
                importStrip
                MusicHallMiniPlayer(controller: controller) {
                    if let pack = controller.activePack,
                       let song = library.songs.first(where: { $0.id == pack.id }) {
                        onOpen(song)
                    }
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 22)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(PixelDotPattern())
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "fpgasong") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { library.importPack(from: url) }
            case .failure(let error):
                library.setImportError(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showCatalogConfig) {
            MusicHallCatalogConfigSheet(library: library)
        }
        .alert(
            "删除本地包？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { song in
            Button("删除", role: .destructive) {
                controller.stop {
                    library.delete(song)
                    pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { song in
            Text("只删除 iPad 上的「\(song.title)」缓存；不会删除在线曲库或设备缓存状态。")
        }
    }

    private var intro: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("音乐厅")
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text("完整歌曲包下载、iPad 缓存、ESP 传输与 FPGA 定时演奏")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                Text("首曲 Rock Theme 3 · Umplix · CC0 来源 OpenGameArt · 器乐改编")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
            }
            Spacer(minLength: 0)
            CosmicArchiveStamp(index: "01")
            MusicHallDevStatusTag()
        }
    }

    private var catalogStrip: some View {
        HStack(spacing: 9) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
            VStack(alignment: .leading, spacing: 2) {
                Text(library.catalogState)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                if !library.catalogURLText.isEmpty {
                    Text(library.catalogURLText)
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if library.isRefreshingCatalog {
                ProgressView()
                    .controlSize(.small)
            }
            Button("曲库设置") { showCatalogConfig = true }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 10,
                        horizontalPadding: 9,
                        verticalPadding: 5
                    )
                )
            Button("导入文件") { showImporter = true }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 10,
                        horizontalPadding: 9,
                        verticalPadding: 5,
                        foreground: PixelPalette.accentDark,
                        border: PixelPalette.accent.opacity(0.55)
                    )
                )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(PixelPanelShape(cut: 5).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 5).stroke(PixelPalette.line, lineWidth: 1))
    }

    private var importStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本地测试与导入")
                .font(.system(size: 12, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text("支持 Files 导入 .fpgasong。导入包只标记为“文件导入”，不伪装成在线下载；连接设备后仍需重新传输和确认预装载。")
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("从“文件”导入 .fpgasong") { showImporter = true }
                    .buttonStyle(
                        PixelOutlineButtonStyle(
                            fontSize: 11,
                            horizontalPadding: 11,
                            verticalPadding: 6
                        )
                    )
                if let error = library.lastError {
                    Text(error)
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.miss)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(PixelPanelShape(cut: 6).fill(PixelPalette.secondary.opacity(0.55)))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("缓存 / 传输 / 演奏是三件事")
                .font(.system(size: 10, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text("已缓存到 iPad 只代表本地包通过校验；设备缓存、预装载和播放进度必须由设备回传。没有真实曲库地址时不提供假下载。")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Spacer(minLength: 0)
        }
    }
}

private struct MusicHallDevStatusTag: View {
    @EnvironmentObject private var bluetooth: InstrumentBluetooth

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(bluetooth.isPerformanceSinkAvailable ? "BLE 能力已确认" : "BLE 未就绪")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(bluetooth.isPerformanceSinkAvailable ? PixelPalette.good : PixelPalette.muted)
            Text(bluetooth.performanceSinkDescription)
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(PixelPanelShape(cut: 4).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 4).stroke(PixelPalette.line, lineWidth: 0.8))
    }
}

private struct MusicHallHeroCard: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    let song: MusicHallSong
    let onOpen: (MusicHallSong) -> Void

    var body: some View {
        HStack(spacing: 16) {
            MusicHallCoverView(pack: song.local, catalog: song.catalog, title: song.title)
                .frame(width: 164, height: 164)
            VStack(alignment: .leading, spacing: 7) {
                Text("首曲 · 器乐改编")
                    .font(.system(size: 9, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                Text(song.title)
                    .font(.system(size: 27, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                    .lineLimit(2)
                Text("\(song.artist) · \(song.sourceName) · \(musicHallDurationText(song.durationSeconds))")
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                if let arrangement = song.arrangement {
                    Text(arrangement)
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                        .lineLimit(3)
                }
                HStack(spacing: 7) {
                    PixelTag(text: song.isCached ? "已缓存到 iPad" : "尚未下载到 iPad",
                             foreground: song.isCached ? PixelPalette.good : PixelPalette.muted,
                             fill: PixelPalette.card,
                             border: PixelPalette.line)
                    PixelTag(text: "FPGA 演奏需真实能力",
                             foreground: PixelPalette.muted,
                             fill: PixelPalette.card,
                             border: PixelPalette.line)
                }
                MusicHallDownloadAction(
                    library: library,
                    controller: controller,
                    song: song,
                    onOpen: onOpen
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 10))
        .overlay(PixelPanelShape(cut: 10).stroke(PixelPalette.accent.opacity(0.4), lineWidth: 1.5))
    }
}

private struct MusicHallSongRow: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    let song: MusicHallSong
    let onOpen: (MusicHallSong) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            MusicHallCoverView(pack: song.local, catalog: song.catalog, title: song.title)
                .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                        .lineLimit(1)
                    if song.local != nil {
                        PixelTag(
                            text: song.local?.origin.title ?? "本地",
                            foreground: PixelPalette.good,
                            fill: PixelPalette.card,
                            border: PixelPalette.good.opacity(0.35)
                        )
                    }
                }
                Text("\(song.artist) · \(song.sourceName) · \(musicHallDurationText(song.durationSeconds))")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(1)
                if let arrangement = song.arrangement {
                    Text(arrangement)
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                        .lineLimit(1)
                }
                MusicHallDownloadAction(
                    library: library,
                    controller: controller,
                    song: song,
                    onOpen: onOpen
                )
            }
            Spacer(minLength: 0)
            if song.isCached {
                Button("删除缓存", action: onDelete)
                    .buttonStyle(
                        PixelOutlineButtonStyle(
                            fontSize: 9,
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            foreground: PixelPalette.miss,
                            border: PixelPalette.miss.opacity(0.45)
                        )
                    )
            }
        }
        .padding(10)
        .background(PixelPanelShape(cut: 6).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private struct MusicHallDownloadAction: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    let song: MusicHallSong
    let onOpen: (MusicHallSong) -> Void

    private var progress: MusicHallDownloadProgress {
        library.progress(for: song.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if song.isCached {
                    Button("打开播放页") { onOpen(song) }
                        .buttonStyle(
                            PixelFilledButtonStyle(
                                fontSize: 10,
                                horizontalPadding: 10,
                                verticalPadding: 5
                            )
                        )
                } else {
                    switch progress.phase {
                    case .downloading, .verifying, .installing:
                        ProgressView(value: progress.phase == .verifying ? 1 : progress.fraction)
                            .frame(width: 116)
                        Text(progress.message)
                            .font(.system(size: 9, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                            .lineLimit(1)
                        Button("取消") { library.cancelDownload(song.id) }
                            .buttonStyle(
                                PixelOutlineButtonStyle(
                                    fontSize: 9,
                                    horizontalPadding: 7,
                                    verticalPadding: 4
                                )
                            )
                    case .failed(let message):
                        Text(message)
                            .font(.system(size: 9, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.miss)
                            .lineLimit(2)
                        Button("重试下载") { library.retry(song) }
                            .buttonStyle(
                                PixelOutlineButtonStyle(
                                    fontSize: 9,
                                    horizontalPadding: 8,
                                    verticalPadding: 4
                                )
                            )
                    default:
                        if song.downloadURL == nil {
                            Text("在线源未配置；请先设置真实在线曲库，或从文件导入")
                                .font(.system(size: 9, weight: .medium, design: .serif))
                                .foregroundStyle(PixelPalette.muted)
                                .lineLimit(2)
                        } else if (song.catalog?.packSha256 ?? "").isEmpty
                                    || (song.catalog?.packBytes ?? 0) <= 0 {
                            Text("目录缺少包大小/SHA-256；App 拒绝下载")
                                .font(.system(size: 9, weight: .medium, design: .serif))
                                .foregroundStyle(PixelPalette.miss)
                        } else {
                            Button("下载到 iPad") { library.download(song) }
                                .buttonStyle(
                                    PixelFilledButtonStyle(
                                        fontSize: 10,
                                        horizontalPadding: 10,
                                        verticalPadding: 5
                                    )
                                )
                        }
                    }
                }
            }
        }
    }
}

private struct MusicHallCatalogConfigSheet: View {
    @ObservedObject var library: MusicHallLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = MusicHallConfiguration.catalogURLText
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("在线曲库设置")
                    .font(.system(size: 20, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Spacer()
                Button("关闭") { dismiss() }
            }
            Text("填写真实 HTTPS catalog.json 地址；也可以填开发局域网地址。App 只缓存已校验的包，不会把占位按钮显示成已下载。")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            TextField("https://…/catalog.json", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            if let errorText {
                Text(errorText)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
            }
            HStack(spacing: 8) {
                Button("保存并刷新") {
                    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        library.saveCatalogURL("")
                        dismiss()
                        return
                    }
                    guard let url = URL(string: trimmed),
                          let scheme = url.scheme?.lowercased(),
                          (scheme == "https" || scheme == "http"),
                          url.host != nil else {
                        errorText = "请输入有效 http/https 地址"
                        return
                    }
                    library.saveCatalogURL(trimmed)
                    dismiss()
                }
                .buttonStyle(PixelFilledButtonStyle(fontSize: 12))
                Button("只使用本地导入") {
                    library.saveCatalogURL("")
                    dismiss()
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 11))
            }
            Text("开发提示：iOS ATS 可能拦截明文 http；正式地址应使用 HTTPS。局域网测试也可先用 Files 导入完整包。")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 560)
        .background(PixelPalette.background)
    }
}
