import SwiftUI
import UIKit

struct MusicHallCoverView: View {
    let pack: MusicHallLocalPack?
    let catalog: MusicHallCatalogSong?
    let title: String
    var compact: Bool = false

    var body: some View {
        Group {
            if let data = pack?.coverData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                MusicHallPixelCover(title: title, subtitle: catalog?.artist ?? pack?.artist)
            }
        }
        .clipShape(PixelPanelShape(cut: compact ? 4 : 8))
        .overlay(
            PixelPanelShape(cut: compact ? 4 : 8)
                .stroke(PixelPalette.line, lineWidth: 1.2)
        )
    }
}

private struct MusicHallPixelCover: View {
    let title: String
    let subtitle: String?

    var body: some View {
        ZStack {
            PaperPalette.paperDeep
            Group {
                if let image = PaperOrbitMedia.image(named: "paper-orbit-reference") {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .opacity(0.38)
            .blur(radius: 0.3)
            PaperGrain(opacity: 0.30)
            VStack(spacing: 5) {
                PaperOrbitMark(size: 38)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundStyle(PaperPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 7, weight: .regular, design: .serif))
                        .foregroundStyle(PaperPalette.inkSoft)
                        .lineLimit(1)
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.8), lineWidth: 0.7)
            )
            .padding(8)
        }
        .clipped()
        .accessibilityLabel("\(title) 纸上封面")
    }
}
struct MusicHallStageView: View {
    let pack: MusicHallLocalPack
    @ObservedObject var controller: MusicHallController

    private let cues: [MusicHallPerformanceEvent]
    private let sectionInfo: [(start: TimeInterval, end: TimeInterval, title: String, active: [MusicHallInstrument], light: String)]

    init(pack: MusicHallLocalPack, controller: MusicHallController) {
        self.pack = pack
        self.controller = controller
        self.cues = pack.performance.events.filter(\.isCue)
        self.sectionInfo = MusicHallStageView.makeSections(pack: pack)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let time = controller.displayTime(now: now)
            let snapshot = snapshot(at: time)
            ZStack {
                stageBackground(snapshot: snapshot)
                VStack(spacing: 8) {
                    HStack {
                        Text(snapshot.sectionTitle)
                            .font(.system(size: 12, weight: .heavy, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Spacer(minLength: 0)
                        Text(modeLabel)
                            .font(.system(size: 8, weight: .bold, design: .serif))
                            .foregroundStyle(modeColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(PixelPalette.card.opacity(0.74))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(modeColor.opacity(0.4), lineWidth: 0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HStack(alignment: .bottom, spacing: 12) {
                        MusicHallMusicianView(kind: .piano, pulse: snapshot.pulses[.piano] ?? 0)
                        MusicHallMusicianView(kind: .guitar, pulse: snapshot.pulses[.guitar] ?? 0)
                        MusicHallMusicianView(kind: .drums, pulse: snapshot.pulses[.drums] ?? 0)
                    }
                    .padding(.horizontal, 22)

                    HStack(spacing: 8) {
                        ForEach(MusicHallInstrument.allCases) { instrument in
                            MusicHallInstrumentChip(
                                instrument: instrument,
                                pulse: snapshot.pulses[instrument] ?? 0
                            )
                        }
                    }
                    .padding(.bottom, 9)
                }
            }
        }
    }

    private var modeLabel: String {
        switch controller.mode {
        case .none:
            return "待机"
        case .stagePreview:
            return "静音舞台预览"
        case .fpga:
            if controller.stopUnconfirmed { return "停止未确认" }
            if controller.phase == .starting { return "等待 ESP PLAY 状态" }
            if controller.playbackClockIsEstimated { return "ESP 播放流（动画估算，FPGA 无回执）" }
            return "ESP 播放流（FPGA 无回执）"
        }
    }

    private var modeColor: Color {
        if controller.stopUnconfirmed { return PixelPalette.miss }
        if controller.mode == .fpga && controller.phase == .starting { return PixelPalette.accentDark }
        return controller.mode == .fpga ? PixelPalette.good : PixelPalette.accentDark
    }

    private func stageBackground(snapshot: MusicHallStageSnapshot) -> some View {
        ZStack {
            PaperPalette.paperDeep.opacity(0.54)
            PaperGrain(opacity: 0.26)
            Circle()
                .fill(PaperPalette.red.opacity(0.035 + snapshot.light * 0.055))
                .frame(width: 310, height: 310)
                .blur(radius: 26)
                .offset(y: -48)
            Ellipse()
                .stroke(PaperPalette.pencil.opacity(0.25), lineWidth: 0.8)
                .frame(width: 420, height: 180)
                .rotationEffect(.degrees(-8))
                .offset(y: -18)
            Rectangle()
                .fill(PaperPalette.pencil.opacity(0.35))
                .frame(height: 0.8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 30)
                .padding(.bottom, 38)
        }
        .clipShape(PixelPanelShape(cut: 10))
    }

    private func snapshot(at time: TimeInterval) -> MusicHallStageSnapshot {
        let isPlaying = controller.phase == .playing
        let pulses = isPlaying ? pulseMap(at: time) : [:]
        let section = activeSection(at: time)
        return MusicHallStageSnapshot(
            sectionTitle: section?.title ?? "等待段落",
            activeTracks: section?.active ?? [],
            pulses: pulses,
            light: pulses.values.max() ?? 0
        )
    }

    private func pulseMap(at time: TimeInterval) -> [MusicHallInstrument: Double] {
        var result: [MusicHallInstrument: Double] = [:]
        for instrument in MusicHallInstrument.allCases {
            if let cue = lastCue(for: instrument, before: time) {
                let age = max(time - cue.time, 0)
                let envelope = max(0, 1 - age / 0.42)
                let velocity = Double(min(max(cue.velocity, 0), 15)) / 15.0
                result[instrument] = envelope * velocity
            } else {
                result[instrument] = 0
            }
        }
        return result
    }

    private func lastCue(for instrument: MusicHallInstrument, before time: TimeInterval) -> MusicHallPerformanceEvent? {
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].time <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low > 0 else { return nil }
        var index = low - 1
        let lower = max(0, low - 64)
        while index >= lower {
            let cue = cues[index]
            if cue.instrument == instrument {
                return cue
            }
            index -= 1
        }
        return nil
    }

    private func activeSection(at time: TimeInterval) -> (title: String, active: [MusicHallInstrument])? {
        guard !sectionInfo.isEmpty else { return nil }
        var current = sectionInfo[0]
        for item in sectionInfo where time + 0.001 >= item.start {
            current = item
        }
        return (current.title, current.active)
    }

    private static func makeSections(
        pack: MusicHallLocalPack
    ) -> [(start: TimeInterval, end: TimeInterval, title: String, active: [MusicHallInstrument], light: String)] {
        if let stageSections = pack.stage?.sections, !stageSections.isEmpty {
            return stageSections.map { section in
                let start = pack.score.startSeconds(forBar: section.barStart)
                let end = pack.score.startSeconds(forBar: section.barEnd + 1)
                let active = (section.activeTracks ?? []).compactMap { name in
                    MusicHallInstrument(rawValue: name == "guitar" ? "guitar" : name)
                }
                return (start, end, section.title, active, section.lightHint ?? "warm")
            }
        }
        let total = max(pack.durationSeconds, 0.1)
        let sections = pack.score.sections ?? [
            MusicHallScoreSection(startBar: 1, endBar: 1, title: "全曲")
        ]
        return sections.map { section in
            let start = pack.score.startSeconds(forBar: section.startBar)
            let end = section.endBar > section.startBar
                ? pack.score.startSeconds(forBar: section.endBar + 1)
                : min(start + total / Double(max(sections.count, 1)), total)
            return (start, end, section.title, MusicHallInstrument.allCases, "warm")
        }
    }
}

struct MusicHallStageSnapshot {
    let sectionTitle: String
    let activeTracks: [MusicHallInstrument]
    let pulses: [MusicHallInstrument: Double]
    let light: Double
}

private struct MusicHallInstrumentChip: View {
    let instrument: MusicHallInstrument
    let pulse: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.32 + pulse * 0.68))
                .frame(width: 5, height: 5)
            Text(instrument.title)
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(PixelPalette.card.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(
                pulse > 0.08 ? color.opacity(0.8) : PixelPalette.line,
                lineWidth: pulse > 0.08 ? 1.4 : 0.7
            )
        )
    }

    private var color: Color {
        switch instrument {
        case .piano: return PixelPalette.accentDark
        case .guitar: return PixelPalette.accent
        case .drums: return PixelPalette.good
        }
    }
}

private struct MusicHallMusicianView: View {
    let kind: MusicHallInstrument
    let pulse: Double

    var body: some View {
        VStack(spacing: 4) {
            PaperInstrumentArt(kind: paperKind)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .scaleEffect(1 + CGFloat(pulse) * 0.035)
                .opacity(0.76 + pulse * 0.24)
                .background {
                    Circle()
                        .fill(PaperPalette.paperWhite.opacity(0.34 + pulse * 0.20))
                        .frame(width: 92, height: 62)
                        .blur(radius: 10)
                }
            Text(kind.title)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PaperPalette.inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(PaperPalette.paperWhite.opacity(0.74))
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .accessibilityLabel("\(kind.title) 演奏状态")
    }

    private var paperKind: PaperInstrumentKind {
        switch kind {
        case .piano: return .piano
        case .guitar: return .guitar
        case .drums: return .drums
        }
    }
}