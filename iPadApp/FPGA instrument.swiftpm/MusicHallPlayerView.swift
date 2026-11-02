import SwiftUI
import Foundation

struct MusicHallPlayerView: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    let song: MusicHallSong
    let onBackToLibrary: () -> Void
    let onUnavailable: () -> Void

    var body: some View {
        Group {
            if let pack = song.local {
                content(pack)
            } else {
                unavailable
            }
        }
    }

    private func content(_ pack: MusicHallLocalPack) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                topLine
                playerHero(pack)
                MusicHallAmbientVideoStageView(controller: controller)

                MusicHallPlaybackProgress(pack: pack, controller: controller)
                MusicHallPlayerControls(
                    library: library,
                    controller: controller,
                    pack: pack,
                    song: song
                )
                HStack(alignment: .top, spacing: 12) {
                    MusicHallTransferPanel(controller: controller, pack: pack)
                    MusicHallDevicePanel(controller: controller, pack: pack)
                }
                MusicHallPlayerNotes(controller: controller, pack: pack)
            }
            .padding(.horizontal, 20)
            .padding(.top, 13)
            .padding(.bottom, 24)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
        .background(PixelDotPattern())
    }

    private var topLine: some View {
        HStack(spacing: 8) {
            Button(action: onBackToLibrary) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold, design: .serif))
                    Text("返回曲库")
                }
                .font(.system(size: 11, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            }
            .buttonStyle(
                PixelOutlineButtonStyle(
                    fontSize: 10,
                    horizontalPadding: 9,
                    verticalPadding: 5
                )
            )
            Text("返回曲库继续当前播放；返回主页会尝试停止，失败时仍可离开")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Spacer(minLength: 0)
            PixelTag(
                text: controller.presentationLabel,
                foreground: controller.stopUnconfirmed ? PixelPalette.miss : (controller.mode == .fpga ? PixelPalette.good : PixelPalette.accentDark),
                fill: PixelPalette.card,
                border: PixelPalette.line
            )
        }
    }

    private func playerHero(_ pack: MusicHallLocalPack) -> some View {
        let playing = controller.phase == .playing
            && (controller.mode == .fpga || controller.mode == .stagePreview)

        return VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 26) {
                    vinyl(pack: pack, playing: playing)
                        .frame(width: 336, height: 336)
                    recordInformation(pack, playing: playing)
                }
                VStack(alignment: .center, spacing: 18) {
                    vinyl(pack: pack, playing: playing)
                        .frame(maxWidth: 340)
                    recordInformation(pack, playing: playing)
                }
            }
        }
        .padding(18)
        .cosmicCard(fill: CosmicPalette.panel.opacity(0.82))
    }

    private func vinyl(pack: MusicHallLocalPack, playing: Bool) -> some View {
        CosmicVinylRecord(isPlaying: playing) {
            MusicHallCoverView(pack: pack, catalog: song.catalog, title: pack.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func recordInformation(_ pack: MusicHallLocalPack, playing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CosmicSectionLabel(
                index: playing ? "SPIN" : "RECORD",
                title: playing ? "唱片正在旋转" : "待机唱片"
            )

            Text(pack.title)
                .font(.system(size: 31, weight: .semibold, design: .serif))
                .foregroundStyle(CosmicPalette.ivory)
                .lineLimit(2)

            Text("\(pack.artist) · \(pack.sourceName)")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(CosmicPalette.ivoryMuted)

            Text("\(musicHallDurationText(pack.durationSeconds)) · \(pack.performance.eventCount) 个演奏事件 · 器乐无歌词")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .foregroundStyle(CosmicPalette.steel)

            if let source = pack.score.source,
               let license = source.license {
                Text("来源：\(source.url ?? "已记录在包内") · \(license)")
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .foregroundStyle(CosmicPalette.steel)
                    .lineLimit(1)
            }

            if let arrangement = pack.arrangement {
                Text(arrangement)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundStyle(CosmicPalette.steel)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                CosmicTag(text: pack.origin.title, color: CosmicPalette.teal)
                CosmicTag(text: "已缓存到 iPad", color: CosmicPalette.teal)
                CosmicTag(text: "设备缓存另算", color: CosmicPalette.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.miss)
            Text("本地包不可用")
                .font(.system(size: 20, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text("曲库条目存在，但 iPad 上尚未缓存完整歌曲包。")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Button("返回曲库", action: onUnavailable)
                .buttonStyle(PixelFilledButtonStyle(fontSize: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelPalette.background)
    }
}

private struct MusicHallPlaybackProgress: View {
    let pack: MusicHallLocalPack
    @ObservedObject var controller: MusicHallController

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let time = controller.displayTime(now: now)
            let progress = controller.progress(now: now)
            let section = sectionTitle(at: time)
            VStack(spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(section)
                        .font(.system(size: 12, weight: .heavy, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    PixelTag(
                        text: controller.phase == .starting ? "等待设备确认" : controller.playbackClockTitle,
                        foreground: controller.phase == .starting ? PixelPalette.accentDark : (controller.playbackClockIsEstimated ? PixelPalette.accentDark : (controller.mode == .fpga ? PixelPalette.good : PixelPalette.muted)),
                        fill: PixelPalette.card,
                        border: PixelPalette.line
                    )
                    Spacer(minLength: 0)
                    Text("\(musicHallDurationText(time)) / \(musicHallDurationText(pack.durationSeconds))")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(PixelPalette.line)
                        Rectangle()
                            .fill(PixelPalette.accent)
                            .frame(width: max(0, geometry.size.width * progress))
                    }
                }
                .frame(height: 7)
                .clipShape(PixelPanelShape(cut: 2))
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 8, weight: .bold, design: .serif))
                    Text("拖动进度：等待设备明确支持；当前只读")
                    Text("·")
                    Text("暂停：等待设备恢复状态；当前不开放")
                }
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            }
            .padding(11)
            .background(PixelPanelShape(cut: 6).fill(PixelPalette.card))
            .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
        }
    }

    private func sectionTitle(at time: TimeInterval) -> String {
        let sections = pack.sections
        guard !sections.isEmpty else { return "乐曲进行中" }
        var title = sections[0].title
        for section in sections {
            let start = pack.score.startSeconds(forBar: section.startBar)
            if time + 0.001 >= start {
                title = section.title
            } else {
                break
            }
        }
        return displaySectionTitle(title)
    }

    private func displaySectionTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("section") || lower.hasPrefix("part") {
            return "乐曲进行中"
        }
        return trimmed.isEmpty ? "乐曲进行中" : trimmed
    }
}

private struct MusicHallPlayerControls: View {
    @ObservedObject var library: MusicHallLibrary
    @ObservedObject var controller: MusicHallController
    @EnvironmentObject private var bluetooth: InstrumentBluetooth
    let pack: MusicHallLocalPack
    let song: MusicHallSong

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("静音舞台预览") {
                    controller.startStagePreview(pack)
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 11))
                .disabled(controller.hasSession || controller.mode == .fpga)

                Button("准备音乐厅（ESP 预装载）") {
                    controller.prepareForHardware(pack)
                }
                .buttonStyle(PixelFilledButtonStyle(fontSize: 11))
                .disabled(!controller.canUseHardware || controller.hasSession)

                Button("开始播放（ESP 状态）") {
                    controller.startHardwarePlayback()
                }
                .buttonStyle(PixelFilledButtonStyle(fontSize: 11, fill: PixelPalette.good, border: PixelPalette.good))
                .disabled(controller.phase != .ready || controller.activePack?.id != pack.id)

                Button(controller.stopUnconfirmed ? "重试停止" : "停止") {
                    controller.stop()
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 11, foreground: PixelPalette.miss, border: PixelPalette.miss.opacity(0.45)))
                .disabled(!controller.hasSession)

                Button("断开并重连") {
                    bluetooth.disconnect()
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 11))
                .disabled(!bluetooth.isReady && !bluetooth.isConnecting)

                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("设备音量")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text("由 FPGA/功放本地控制；当前 BLE 协议未定义远程音量，App 不使用 iPad 音量冒充设备音量。")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                Spacer(minLength: 0)
            }
            if controller.stopUnconfirmed {
                Text("停止未确认：旧硬件会话可能仍在发声；自由演奏被阻止，但可以先返回主页。请点“重试停止”或“断开并重连”。")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.lastError?.contains("存储") == true {
                Text("这是 ESP 内部歌曲存储写入失败，不是 iPad 音乐包缓存。App 本地包无需重下；请重试或重启 ESP。新版 ESP 使用独立文件存储，不再把整首歌曲写入 NVS。")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !controller.canUseHardware {
                Text("音乐厅传输适配器未装载；当前只能使用静音舞台预览。")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .lineLimit(2)
            }
        }
        .padding(11)
        .background(PixelPanelShape(cut: 6).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private struct MusicHallTransferPanel: View {
    @ObservedObject var controller: MusicHallController
    let pack: MusicHallLocalPack

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("设备传输 / 预装载")
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Spacer(minLength: 0)
                Text(controller.phase.title)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(controller.phase == .ready ? PixelPalette.good : PixelPalette.accentDark)
            }
            ProgressView(value: controller.transferFraction)
                .tint(PixelPalette.accent)
            Text(controller.transferMessage)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Text("传输进度与上方下载进度是两套：本面板表示 iPad → ESP 的会话；FPGA 执行无回执。")
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("包 SHA")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                Text(pack.archiveSHA256.map { String($0.prefix(12)) + "…" } ?? "导入包无目录摘要")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                    .lineLimit(1)
            }
            if controller.stopUnconfirmed {
                Text("停止未确认：请重试停止；确认前不会放行自由演奏。")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .failed(_) = controller.phase {
                Button("重新准备") {
                    controller.prepareForHardware(pack)
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 9))
                .disabled(!controller.canUseHardware || controller.hasSession)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(PixelPanelShape(cut: 6).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private struct MusicHallDevicePanel: View {
    @ObservedObject var controller: MusicHallController
    let pack: MusicHallLocalPack
    @EnvironmentObject private var bluetooth: InstrumentBluetooth

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("真实设备状态")
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Spacer(minLength: 0)
                PixelTag(
                    text: bluetooth.isPerformanceSinkAvailable ? "能力已确认" : "未确认",
                    foreground: bluetooth.isPerformanceSinkAvailable ? PixelPalette.good : PixelPalette.muted,
                    fill: PixelPalette.card,
                    border: PixelPalette.line
                )
            }
            row("BLE", bluetooth.isReady ? "已连接" : "未连接")
            row("演奏通道", bluetooth.isPerformanceSinkAvailable ? "可用" : "不可用")
            row("设备协议", bluetooth.capabilityVersion.map { "v\($0)" } ?? "未声明")
            row("能力掩码", bluetooth.capabilityMask.map { String(format: "0x%08X", $0) } ?? "未声明")
            row("能力状态", bluetooth.performanceProtocolStatus)
            if let profile = controller.deviceProfile {
                row("会话协议", "v\(profile.protocolVersion)")
                row("歌曲包上限", "\(profile.maxPackBytes / 1024) KB")
                row("单块上限", "\(profile.maxChunkBytes) B")
            }
            Text("PONG / ATT 写入只证明链路；PLAY state2 是 ESP 接受并开始流传输，不是 FPGA 执行确认；本候选没有硬件 progress。")
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("歌曲要求：\(pack.requiredCapabilities.joined(separator: "、"))")
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            if let missing = controller.deviceProfile?.missingRequirements(for: pack), !missing.isEmpty {
                Text("缺少：\(missing.joined(separator: "、"))")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(PixelPanelShape(cut: 6).fill(PixelPalette.card))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct MusicHallPlayerNotes: View {
    @ObservedObject var controller: MusicHallController
    let pack: MusicHallLocalPack

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本版边界")
                .font(.system(size: 10, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text("静音舞台预览只跟随本地预览时钟，不产生声音；当前 FPGA 候选没有硬件进度，FPGA 演奏页的时间轴是明确标注的估算动画，只用于舞台动作，不代表设备位置，也不由动画帧率触发音符。暂停/拖动/音量远程控制未获设备协议支持时保持禁用。")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !pack.manifest.limitations.isNilOrEmpty {
                Text("包声明的限制：\(pack.manifest.limitations?.joined(separator: "；") ?? "")")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(3)
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
            }
        }
        .padding(10)
        .background(PixelPanelShape(cut: 5).fill(PixelPalette.secondary.opacity(0.5)))
        .overlay(PixelPanelShape(cut: 5).stroke(PixelPalette.line, lineWidth: 0.8))
    }
}

private extension Optional where Wrapped == [String] {
    var isNilOrEmpty: Bool {
        self?.isEmpty != false
    }
}

