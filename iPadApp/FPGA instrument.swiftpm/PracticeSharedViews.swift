import SwiftUI

struct PracticeStatusBar: View {
    @ObservedObject var session: PracticeSession

    var body: some View {
        HStack(spacing: 8) {
            PracticeStatTile(
                title: "分数",
                value: session.stats.score,
                tint: PaperPalette.ink,
                bounces: false
            )
            PracticeStatTile(
                title: "当前连击",
                value: session.stats.combo,
                tint: PaperPalette.red,
                bounces: true
            )
            PracticeStatTile(
                title: "最大连击",
                value: session.stats.maxCombo,
                tint: PaperPalette.red,
                bounces: false
            )
            PracticeProgressTile(
                resolved: session.resolvedCount,
                total: session.totalNotes,
                progress: session.progress
            )
        }
    }
}

struct PracticeStatTile: View {
    let title: String
    let value: Int
    let tint: Color
    let bounces: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(PaperPalette.ink.opacity(0.48))

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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PaperPalette.ink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PaperPalette.ink.opacity(0.07), lineWidth: 1)
        )
    }
}

struct BouncyNumberText: View {
    let value: Int
    let tint: Color

    @State private var scale: CGFloat = 1.0

    init(value: Int, tint: Color) {
        self.value = value
        self.tint = tint
    }

    var body: some View {
        Text("\(value)")
            .font(.system(.title3, design: .serif).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .scaleEffect(scale, anchor: .leading)
            .onChange(of: value) { _, _ in
                scale = 1.14
                withAnimation(.spring(response: 0.24, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

struct PracticeProgressTile: View {
    let resolved: Int
    let total: Int
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("进度")
                    .font(.caption2)
                    .foregroundStyle(PaperPalette.ink.opacity(0.48))
                Spacer(minLength: 2)
                Text("\(resolved)/\(total)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PaperPalette.ink.opacity(0.76))
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(PaperPalette.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PaperPalette.ink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PaperPalette.ink.opacity(0.07), lineWidth: 1)
        )
    }
}

struct PracticePhaseBadge: View {
    let phase: PracticePhase

    var body: some View {
        Text(phaseText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(phaseColor.opacity(0.14)))
    }

    private var phaseText: String {
        switch phase {
        case .idle: return "待开始"
        case .countdown: return "倒计时"
        case .playing: return "进行中"
        case .paused: return "已暂停"
        case .finished: return "已结束"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle: return .gray
        case .countdown: return PaperPalette.red
        case .playing: return PaperPalette.green
        case .paused: return PaperPalette.redDeep
        case .finished: return PaperPalette.red
        }
    }
}

struct PracticeFilledButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PaperPalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

struct PracticeOutlineButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaperPalette.ink.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(PaperPalette.ink.opacity(0.06)))
                .overlay(Capsule().stroke(PaperPalette.ink.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PracticePausedOverlay: View {
    let session: PracticeSession

    var body: some View {
        ZStack {
            PaperPalette.ink.opacity(0.20)

            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 34, design: .serif))
                    .foregroundStyle(PaperPalette.redDeep)

                Text("已暂停")
                    .font(.title2.bold())

                Text("练习时间已冻结。继续后从当前位置恢复，不会跳跃。")
                    .font(.subheadline)
                    .foregroundStyle(PaperPalette.ink.opacity(0.70))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    PracticeFilledButton(
                        title: "继续",
                        systemImage: "play.fill",
                        tint: PaperPalette.red,
                        action: { session.resume() }
                    )

                    PracticeOutlineButton(
                        title: "重新开始",
                        systemImage: "arrow.counterclockwise",
                        action: { session.start() }
                    )
                }
                .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 440)
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
}

struct PracticeResultOverlay: View {
    @ObservedObject var session: PracticeSession
    let subtitle: String
    let onBackHome: () -> Void

    var body: some View {
        ZStack {
            PaperPalette.ink.opacity(0.22)

            VStack(spacing: 12) {
                titleRow
                subtitleText
                scoreRow
                pillsRow
                metricsRow
                checkRow
                buttonsRow
            }
            .padding(22)
            .frame(maxWidth: 510)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.99))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PaperPalette.ink.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.35), radius: 24, y: 10)
            .padding(20)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PaperPalette.green)
            Text("练习结束")
                .font(.title2.bold())
        }
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(PaperPalette.ink.opacity(0.58))
    }

    private var scoreRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(session.stats.score)")
                .font(.system(size: 46, weight: .heavy, design: .serif))
                .monospacedDigit()
            Text("总分")
                .font(.subheadline)
                .foregroundStyle(PaperPalette.ink.opacity(0.58))
        }
    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            ResultPill(title: "Perfect", count: session.stats.perfect, color: PaperPalette.redDeep)
            ResultPill(title: "Good", count: session.stats.good, color: PaperPalette.green)
            ResultPill(title: "Miss", count: session.stats.miss, color: .red)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 28) {
            ResultMetric(title: "最大连击", value: "\(session.stats.maxCombo)")
            ResultMetric(title: "命中率", value: "\(accuracyPercent)%")
        }
    }

    private var checkRow: some View {
        HStack(spacing: 5) {
            Image(systemName: statsMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(
                "Perfect \(session.stats.perfect) + Good \(session.stats.good) + Miss \(session.stats.miss) = \(countedNotes) / \(session.totalNotes) 个音符"
            )
        }
        .font(.caption)
        .foregroundStyle(statsMatch ? PaperPalette.green.opacity(0.9) : PaperPalette.red)
    }

    private var buttonsRow: some View {
        HStack(spacing: 10) {
            PracticeFilledButton(
                title: "再练一次",
                systemImage: "arrow.clockwise",
                tint: PaperPalette.red,
                action: { session.start() }
            )

            PracticeOutlineButton(
                title: "返回主页",
                systemImage: "house.fill",
                action: onBackHome
            )
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

private struct ResultPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }
}

private struct ResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(PaperPalette.ink.opacity(0.48))
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(PaperPalette.ink.opacity(0.9))
        }
    }
}
