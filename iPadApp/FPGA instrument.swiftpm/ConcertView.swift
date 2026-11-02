import Foundation
import SwiftUI

struct ConcertView: View {
    @ObservedObject var playback: ConcertPlayback
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var userReduceMotion: Bool = false

    private var reduceMotionEnabled: Bool {
        systemReduceMotion || userReduceMotion
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            stage
            bottomPanel
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onDisappear {
            playback.pause()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(playback.song.title)
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text("45–60 秒内置事件曲 · 钢琴 / 电吉他 / 九鼓")
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
            }

            Spacer(minLength: 4)

            PixelTag(
                text: "静音预览",
                foreground: PixelPalette.accentDark,
                fill: PixelPalette.secondary,
                border: PixelPalette.line
            )
            PixelTag(
                text: "本地模拟演示 · 未连接 FPGA",
                foreground: PixelPalette.muted,
                fill: PixelPalette.card,
                border: PixelPalette.line
            )
        }
    }

    private var stage: some View {
        ConcertStageView(playback: playback, reduceMotion: reduceMotionEnabled)
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

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            ConcertLiveInfo(playback: playback)
            HStack(spacing: 8) {
                Button(action: { playback.playPause() }) {
                    Label(primaryTitle, systemImage: primaryIcon)
                }
                .buttonStyle(
                    PixelFilledButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 15,
                        verticalPadding: 9
                    )
                )

                Button(action: { playback.restart() }) {
                    Label("重头播放", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 13,
                        verticalPadding: 9
                    )
                )

                Button(action: { playback.stop() }) {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 13,
                        verticalPadding: 9
                    )
                )
                .disabled(playback.phase == .idle)
                .opacity(playback.phase == .idle ? 0.45 : 1)

                Button(action: {
                    if !systemReduceMotion {
                        userReduceMotion.toggle()
                    }
                }) {
                    Label(
                        systemReduceMotion
                            ? "系统减少动态"
                            : (userReduceMotion ? "动态已减少" : "减少动态"),
                        systemImage: "accessibility"
                    )
                }
                .buttonStyle(
                    PixelOutlineButtonStyle(
                        fontSize: 10,
                        horizontalPadding: 9,
                        verticalPadding: 7
                    )
                )
                .disabled(systemReduceMotion)
                .opacity(systemReduceMotion ? 0.65 : 1)

                Spacer(minLength: 4)

                Text("本地模拟演示 · 静音预览 · 未连接 FPGA")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var primaryTitle: String {
        switch playback.phase {
        case .playing:
            return "暂停"
        case .paused:
            return "继续"
        case .finished:
            return "重新播放"
        case .idle:
            return "播放"
        }
    }

    private var primaryIcon: String {
        switch playback.phase {
        case .playing:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .finished:
            return "arrow.clockwise"
        case .idle:
            return "play.fill"
        }
    }
}

private struct ConcertLiveInfo: View {
    @ObservedObject var playback: ConcertPlayback

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let time: TimeInterval = playback.currentTime()
            let duration: TimeInterval = max(playback.song.duration, 1)
            let section = playback.song.section(at: time)
            let fraction: Double = min(max(time / duration, 0), 1)

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Text("段落 · \(section.title)")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    Spacer(minLength: 4)
                    Text("\(formatTime(time)) / \(formatTime(playback.song.duration))")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PixelPalette.secondary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PixelPalette.accent)
                            .frame(width: max(0, geometry.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 7)
            }
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let seconds: Int = max(0, Int(value.rounded(.down)))
        let minutes: Int = seconds / 60
        let remainder: Int = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct ConcertStageView: View {
    @ObservedObject var playback: ConcertPlayback
    let reduceMotion: Bool

    @ViewBuilder
    var body: some View {
        if playback.phase == .playing {
            if reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.12)) { _ in
                    stageCanvas(at: playback.currentTime())
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    stageCanvas(at: playback.currentTime())
                }
            }
        } else {
            stageCanvas(at: playback.currentTime())
        }
    }

    private func stageCanvas(at time: TimeInterval) -> some View {
        Canvas { context, size in
            ConcertStagePainter.draw(
                context: &context,
                size: size,
                song: playback.song,
                time: time,
                reduceMotion: reduceMotion,
                finished: playback.phase == .finished
            )
        }
    }
}

private struct ConcertStagePainter {
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        song: ConcertSong,
        time: TimeInterval,
        reduceMotion: Bool,
        finished: Bool
    ) {
        let width: CGFloat = size.width
        let height: CGFloat = size.height
        guard width > 1, height > 1 else { return }

        fill(context: &context, rect: CGRect(origin: .zero, size: size), color: PixelPalette.background)
        let floorY: CGFloat = height * 0.74
        fill(
            context: &context,
            rect: CGRect(x: 0, y: floorY, width: width, height: height - floorY),
            color: PixelPalette.secondary.opacity(0.42)
        )
        fill(
            context: &context,
            rect: CGRect(x: 0, y: floorY, width: width, height: 1.5),
            color: PixelPalette.accent.opacity(0.55)
        )

        let marks: [(CGFloat, CGFloat, Color)] = [
            (0.08, 0.13, PaperPalette.green),
            (0.28, 0.20, PaperPalette.blue),
            (0.45, 0.11, PaperPalette.red),
            (0.62, 0.17, PaperPalette.pencil),
            (0.92, 0.14, PaperPalette.green)
        ]
        for (x, y, color) in marks {
            let rect = CGRect(
                x: width * x - 3,
                y: height * y - 3,
                width: 6,
                height: 6
            )
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.32)))
        }

        var pianoKeys = Set<Int>()
        var guitarStrings = Set<Int>()
        var drumHits = Set<Int>()
        var latestPiano: ConcertEvent?
        var latestGuitar: ConcertEvent?
        var latestDrums: ConcertEvent?

        for event in song.events {
            let active = time >= event.time && time < event.time + event.duration
            if active {
                switch event.instrument {
                case .piano: pianoKeys.insert(event.value)
                case .guitar: guitarStrings.insert(event.value)
                case .drums: drumHits.insert(event.value)
                }
            }

            let age = time - event.time
            if age >= 0 && age < 0.35 {
                switch event.instrument {
                case .piano:
                    if latestPiano == nil || event.time > latestPiano!.time { latestPiano = event }
                case .guitar:
                    if latestGuitar == nil || event.time > latestGuitar!.time { latestGuitar = event }
                case .drums:
                    if latestDrums == nil || event.time > latestDrums!.time { latestDrums = event }
                }
            }
        }

        let scale: CGFloat = min(width, height)
        let section: ConcertSection = song.section(at: time)

        ConcertStagePets.drawSpotlights(
            context: &context,
            width: width,
            height: height,
            floorY: floorY,
            section: section,
            time: time,
            pianoActive: !pianoKeys.isEmpty,
            guitarActive: !guitarStrings.isEmpty,
            drumsActive: !drumHits.isEmpty,
            latestPiano: latestPiano,
            latestGuitar: latestGuitar,
            latestDrums: latestDrums,
            reduceMotion: reduceMotion
        )
        ConcertStagePets.drawPets(
            context: &context,
            width: width,
            height: height,
            floorY: floorY,
            scale: scale,
            time: time,
            pianoActive: !pianoKeys.isEmpty,
            guitarActive: !guitarStrings.isEmpty,
            drumsActive: !drumHits.isEmpty,
            latestPiano: latestPiano,
            latestGuitar: latestGuitar,
            latestDrums: latestDrums,
            reduceMotion: reduceMotion,
            finished: finished
        )


        if !reduceMotion {
            for event in song.events {
                let age = time - event.time
                guard age >= 0 && age < 0.25 else { continue }
                drawParticles(context: &context, size: size, event: event, age: age)
            }
        }

    }

    private static func drawPianoGroup(
        context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        floorY: CGFloat,
        keys: Set<Int>,
        latest: ConcertEvent?
    ) {
        let scale: CGFloat = min(width, height)
        let centerX: CGFloat = width * 0.18
        let keyboardWidth: CGFloat = width * 0.17
        let keyboardHeight: CGFloat = max(18, height * 0.08)
        let keyboardX: CGFloat = centerX - keyboardWidth * 0.5
        let keyboardY: CGFloat = height * 0.63

        fill(
            context: &context,
            rect: CGRect(x: keyboardX - 4, y: keyboardY - 4, width: keyboardWidth + 8, height: keyboardHeight + 8),
            color: PixelPalette.ink
        )
        let keyWidth: CGFloat = keyboardWidth / 8.0
        for key in 0..<8 {
            let keyRect = CGRect(
                x: keyboardX + CGFloat(key) * keyWidth + 1,
                y: keyboardY,
                width: keyWidth - 2,
                height: keyboardHeight
            )
            fill(
                context: &context,
                rect: keyRect,
                color: keys.contains(key) ? PixelPalette.accent : PixelPalette.card
            )
            stroke(
                context: &context,
                rect: keyRect,
                color: PixelPalette.line,
                lineWidth: 1
            )
        }

        let activeKey: Int = keys.sorted().first ?? 3
        let handX: CGFloat = keyboardX + CGFloat(activeKey + 1) * keyWidth - keyWidth * 0.5
        let handY: CGFloat = keyboardY - 2
        let pianoShoulderY: CGFloat = floorY - scale * 0.125
        drawArm(
            context: &context,
            from: CGPoint(x: centerX - scale * 0.014, y: pianoShoulderY),
            to: CGPoint(x: handX, y: handY),
            scale: scale
        )
        drawHand(context: &context, x: handX, y: handY, scale: scale, color: PixelPalette.ink)
        if let latest {
            let handBounce: CGFloat = CGFloat(latest.velocity) * 3.0
            drawHand(context: &context, x: handX + keyWidth * 0.6, y: handY - handBounce, scale: scale, color: PixelPalette.ink)
        }
    }

    private static func drawGuitarGroup(
        context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        floorY: CGFloat,
        strings: Set<Int>,
        latest: ConcertEvent?,
        time: TimeInterval
    ) {
        let scale: CGFloat = min(width, height)
        let centerX: CGFloat = width * 0.50
        let bodyCenter = CGPoint(x: centerX + width * 0.035, y: height * 0.62)
        let bodySize = CGSize(width: width * 0.075, height: height * 0.12)
        let neckRect = CGRect(
            x: centerX - width * 0.10,
            y: bodyCenter.y - height * 0.026,
            width: width * 0.13,
            height: height * 0.052
        )

        fill(context: &context, rect: neckRect, color: PixelPalette.ink)
        fill(
            context: &context,
            rect: CGRect(x: neckRect.minX - 8, y: neckRect.minY + 3, width: 8, height: neckRect.height - 6),
            color: PixelPalette.accentDark
        )
        fillEllipse(
            context: &context,
            rect: CGRect(
                x: bodyCenter.x - bodySize.width / 2,
                y: bodyCenter.y - bodySize.height / 2,
                width: bodySize.width,
                height: bodySize.height
            ),
            color: PixelPalette.accent
        )
        fillEllipse(
            context: &context,
            rect: CGRect(
                x: bodyCenter.x - bodySize.width * 0.18,
                y: bodyCenter.y - bodySize.height * 0.16,
                width: bodySize.width * 0.36,
                height: bodySize.height * 0.32
            ),
            color: PixelPalette.secondary
        )

        let stringStartX: CGFloat = neckRect.minX
        let stringEndX: CGFloat = bodyCenter.x + bodySize.width * 0.35
        let stringSpacing: CGFloat = height * 0.0105
        for stringIndex in 0..<6 {
            let offset: CGFloat = (2.5 - CGFloat(stringIndex)) * stringSpacing
            let stringY: CGFloat = bodyCenter.y + offset
            let active: Bool = strings.contains(stringIndex)
            let wobble: CGFloat = active ? CGFloat(sin(time * 42.0 + Double(stringIndex))) * 2.0 : 0
            let line = CGRect(
                x: stringStartX,
                y: stringY + wobble,
                width: stringEndX - stringStartX,
                height: active ? 1.8 : 1.0
            )
            fill(
                context: &context,
                rect: line,
                color: active ? PixelPalette.accentDark : PixelPalette.card
            )
        }

        if let latest {
            let stringIndex: Int = min(max(latest.value, 0), 5)
            let offset: CGFloat = (2.5 - CGFloat(stringIndex)) * stringSpacing
            let pickX: CGFloat = stringEndX - width * 0.018
            let pickY: CGFloat = bodyCenter.y + offset
            drawArm(
                context: &context,
                from: CGPoint(x: centerX - width * 0.050, y: floorY - scale * 0.125),
                to: CGPoint(x: pickX, y: pickY - CGFloat(latest.velocity) * 5.0),
                scale: scale
            )
            drawHand(
                context: &context,
                x: pickX,
                y: pickY - CGFloat(latest.velocity) * 5.0,
                scale: scale,
                color: PixelPalette.ink
            )
        } else {
            drawHand(
                context: &context,
                x: stringEndX - width * 0.018,
                y: bodyCenter.y + stringSpacing,
                scale: scale,
                color: PixelPalette.ink
            )
        }
    }

    private static func drawDrumGroup(
        context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        floorY: CGFloat,
        hits: Set<Int>,
        latest: ConcertEvent?
    ) {
        let scale: CGFloat = min(width, height)
        let centerX: CGFloat = width * 0.82
        let centerY: CGFloat = height * 0.62

        let miniPoints: [CGPoint] = drumMiniPoints(width: width, height: height, centerX: centerX, centerY: centerY)
        let miniSizes: [CGSize] = drumMiniSizes(width: width, height: height)
        let isCymbal: [Bool] = [false, false, true, true, true, true, false, false, false]

        for index in 0..<miniPoints.count {
            let point = miniPoints[index]
            let ellipseSize = miniSizes[index]
            let rect = CGRect(
                x: point.x - ellipseSize.width / 2,
                y: point.y - ellipseSize.height / 2,
                width: ellipseSize.width,
                height: ellipseSize.height
            )
            fillEllipse(
                context: &context,
                rect: rect,
                color: hits.contains(index) ? PixelPalette.accent : PixelPalette.card
            )
            strokeEllipse(
                context: &context,
                rect: rect,
                color: isCymbal[index] ? PixelPalette.accentDark : PixelPalette.ink,
                lineWidth: 1
            )
        }

        if let latest {
            let index: Int = min(max(latest.value, 0), miniPoints.count - 1)
            let point = miniPoints[index]
            drawArm(
                context: &context,
                from: CGPoint(x: centerX + scale * 0.014, y: floorY - scale * 0.125),
                to: CGPoint(x: point.x, y: point.y - CGFloat(latest.velocity) * 5.0),
                scale: scale
            )
            drawHand(
                context: &context,
                x: point.x,
                y: point.y - CGFloat(latest.velocity) * 5.0,
                scale: scale,
                color: PixelPalette.ink
            )
        } else {
            drawHand(
                context: &context,
                x: centerX - width * 0.03,
                y: centerY - height * 0.06,
                scale: scale,
                color: PixelPalette.ink
            )
        }
    }

    private static func drumMiniPoints(
        width: CGFloat,
        height: CGFloat,
        centerX: CGFloat,
        centerY: CGFloat
    ) -> [CGPoint] {
        return [
            CGPoint(x: centerX, y: centerY + height * 0.055),
            CGPoint(x: centerX - width * 0.055, y: centerY + height * 0.005),
            CGPoint(x: centerX - width * 0.090, y: centerY - height * 0.012),
            CGPoint(x: centerX - width * 0.090, y: centerY - height * 0.060),
            CGPoint(x: centerX - width * 0.085, y: centerY - height * 0.100),
            CGPoint(x: centerX + width * 0.080, y: centerY - height * 0.090),
            CGPoint(x: centerX - width * 0.025, y: centerY - height * 0.085),
            CGPoint(x: centerX + width * 0.005, y: centerY - height * 0.105),
            CGPoint(x: centerX + width * 0.045, y: centerY - height * 0.060)
        ]
    }

    private static func drumMiniSizes(width: CGFloat, height: CGFloat) -> [CGSize] {
        return [
            CGSize(width: width * 0.060, height: height * 0.042),
            CGSize(width: width * 0.042, height: height * 0.018),
            CGSize(width: width * 0.036, height: height * 0.014),
            CGSize(width: width * 0.036, height: height * 0.014),
            CGSize(width: width * 0.052, height: height * 0.020),
            CGSize(width: width * 0.050, height: height * 0.020),
            CGSize(width: width * 0.034, height: height * 0.016),
            CGSize(width: width * 0.036, height: height * 0.016),
            CGSize(width: width * 0.036, height: height * 0.016)
        ]
    }

    private static func drawParticles(
        context: inout GraphicsContext,
        size: CGSize,
        event: ConcertEvent,
        age: TimeInterval
    ) {
        let groupX: CGFloat
        let groupY: CGFloat
        switch event.instrument {
        case .piano:
            groupX = size.width * 0.18
            groupY = size.height * 0.60
        case .guitar:
            groupX = size.width * 0.50
            groupY = size.height * 0.60
        case .drums:
            groupX = size.width * 0.82
            groupY = size.height * 0.60
        }

        let count: Int = 2 + Int(event.velocity * 2.0)
        let fade: Double = max(0, 1 - age / 0.25)
        for index in 0..<count {
            let offset: CGFloat = CGFloat(index - count / 2) * 5.0
            let rise: CGFloat = CGFloat(age / 0.25) * 14.0
            let rect = CGRect(
                x: groupX + offset,
                y: groupY - 20 - rise - CGFloat(index % 2) * 4,
                width: index % 2 == 0 ? 4 : 3,
                height: index % 2 == 0 ? 4 : 3
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(PaperPalette.red.opacity(0.28 + fade * 0.42))
            )
        }
    }

    private static func drawPerson(
        context: inout GraphicsContext,
        centerX: CGFloat,
        floorY: CGFloat,
        scale: CGFloat,
        bodyColor: Color,
        active: Bool
    ) {
        let bodyWidth: CGFloat = max(12, scale * 0.048)
        let bodyHeight: CGFloat = max(20, scale * 0.085)
        let headSize: CGFloat = max(10, scale * 0.034)
        let legHeight: CGFloat = max(12, scale * 0.060)
        let bodyTop: CGFloat = floorY - legHeight - bodyHeight
        let headTop: CGFloat = bodyTop - headSize

        fill(
            context: &context,
            rect: CGRect(x: centerX - headSize / 2, y: headTop, width: headSize, height: headSize),
            color: PixelPalette.card
        )
        fill(
            context: &context,
            rect: CGRect(x: centerX - bodyWidth / 2, y: bodyTop, width: bodyWidth, height: bodyHeight),
            color: bodyColor
        )
        fill(
            context: &context,
            rect: CGRect(x: centerX - bodyWidth * 0.30, y: floorY - legHeight, width: bodyWidth * 0.24, height: legHeight),
            color: PixelPalette.ink
        )
        fill(
            context: &context,
            rect: CGRect(x: centerX + bodyWidth * 0.08, y: floorY - legHeight, width: bodyWidth * 0.24, height: legHeight),
            color: PixelPalette.ink
        )
        fill(
            context: &context,
            rect: CGRect(x: centerX - headSize * 0.28, y: headTop + headSize * 0.42, width: 2, height: 2),
            color: PixelPalette.ink
        )
        fill(
            context: &context,
            rect: CGRect(x: centerX + headSize * 0.12, y: headTop + headSize * 0.42, width: 2, height: 2),
            color: PixelPalette.ink
        )
        if active {
            fill(
                context: &context,
                rect: CGRect(x: centerX - bodyWidth * 0.18, y: bodyTop + bodyHeight * 0.25, width: bodyWidth * 0.36, height: 3),
                color: PixelPalette.card.opacity(0.65)
            )
        }
    }

    private static func drawArm(
        context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        scale: CGFloat
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(PixelPalette.ink),
            lineWidth: max(2, scale * 0.008)
        )
    }

    private static func drawHand(
        context: inout GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        color: Color
    ) {
        let size: CGFloat = max(4, scale * 0.012)
        fill(
            context: &context,
            rect: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size),
            color: color
        )
    }

    private static func fill(context: inout GraphicsContext, rect: CGRect, color: Color) {
        context.fill(Path(rect), with: .color(color))
    }

    private static func stroke(context: inout GraphicsContext, rect: CGRect, color: Color, lineWidth: CGFloat) {
        context.stroke(Path(rect), with: .color(color), lineWidth: lineWidth)
    }

    private static func fillEllipse(context: inout GraphicsContext, rect: CGRect, color: Color) {
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private static func strokeEllipse(context: inout GraphicsContext, rect: CGRect, color: Color, lineWidth: CGFloat) {
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lineWidth)
    }
}
