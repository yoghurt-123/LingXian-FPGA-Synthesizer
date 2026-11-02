import SwiftUI

struct GuitarLeftHandPanel: View {
    @ObservedObject var session: GuitarPracticeSession
    @State private var showAllFrets: Bool = false

    private let firstFrets: [FPGAFretKey] = Array(FPGAKeyMap.frets.prefix(7))
    private let secondFrets: [FPGAFretKey] = Array(FPGAKeyMap.frets.dropFirst(7))
    private let quickFrets: [FPGAFretKey] = FPGAKeyMap.frets.filter {
        [0, 2, 3, 5].contains($0.fret)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
            let target: GuitarNote? = session.upcomingTarget(
                at: session.practiceTime,
                within: session.guitarChart.practiceChart.previewDuration
            )
            let targetFret: Int? = target?.left.fretNumber
            let targetChord: Int? = target?.left.chordID

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("左手")
                        .font(.system(size: 12, weight: .heavy, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    Text(currentLabel)
                        .font(.system(size: 23, weight: .heavy, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text("0–12品")
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                }

                HStack(spacing: 4) {
                    Text("下一音")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                    Text(targetText(target))
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.accentDark)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if target != nil {
                        Text("先选左手，再拨弦")
                            .font(.system(size: 8, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                }

                HStack(spacing: 4) {
                    Text("常用")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    ForEach(quickFrets) { item in
                        GuitarFretChoice(
                            item: item,
                            isSelected: session.selectedChordID == nil && session.selectedFret == item.fret,
                            isTarget: targetChord == nil && targetFret == Optional(item.fret)
                        ) {
                            session.selectFret(item.fret)
                        }
                    }
                }

                Button {
                    showAllFrets.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAllFrets ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold, design: .serif))
                        Text(showAllFrets ? "收起全部品位" : "展开全部 0–12 品")
                            .font(.system(size: 9, weight: .bold, design: .serif))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(PixelPalette.ink)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(PixelPalette.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                if showAllFrets {
                    HStack(spacing: 3) {
                        ForEach(firstFrets) { item in
                            GuitarFretChoice(
                                item: item,
                                isSelected: session.selectedChordID == nil && session.selectedFret == item.fret,
                                isTarget: targetChord == nil && targetFret == Optional(item.fret)
                            ) {
                                session.selectFret(item.fret)
                            }
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(secondFrets) { item in
                            GuitarFretChoice(
                                item: item,
                                isSelected: session.selectedChordID == nil && session.selectedFret == item.fret,
                                isTarget: targetChord == nil && targetFret == Optional(item.fret)
                            ) {
                                session.selectFret(item.fret)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 5) {
                    Text("和弦")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    Text("U I O P")
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)

                HStack(spacing: 4) {
                    ForEach(FPGAKeyMap.guitarChords) { chord in
                        GuitarChordChoice(
                            chord: chord,
                            isSelected: session.selectedChordID == chord.id,
                            isTarget: targetChord == Optional(chord.id)
                        ) {
                            session.selectChord(chord.id)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: session.leftFeedback.contains("未匹配") ? "exclamationmark.triangle.fill" : "hand.point.up.left.fill")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundStyle(session.leftFeedback.contains("未匹配") ? PixelPalette.miss : PixelPalette.accentDark)
                    Text(session.leftFeedback)
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundStyle(session.leftFeedback.contains("未匹配") ? PixelPalette.miss : PixelPalette.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(minHeight: 22, alignment: .topLeading)

                Spacer(minLength: 0)

                Text("默认以空弦/2品为主；换品前有空白准备。完整 0–12 品在展开面板中，手动选择，不自动切品。")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentLabel: String {
        if let id = session.selectedChordID {
            return FPGAKeyMap.guitarChords.first { $0.id == id }?.name ?? "和弦"
        }
        return "\(session.selectedFret)品"
    }

    private func targetText(_ target: GuitarNote?) -> String {
        guard let target else { return "等待下一音" }
        return "\(target.left.displayText) · \(target.string.displayLabel)"
    }
}
private struct GuitarFretChoice: View {
    let item: FPGAFretKey
    let isSelected: Bool
    let isTarget: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(item.fret)品")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(isSelected ? PixelPalette.card : PixelPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(item.compactKey)
                    .font(.system(size: 8, weight: .semibold, design: .serif))
                    .foregroundStyle(isSelected ? PixelPalette.card : PixelPalette.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? PixelPalette.accent : PixelPalette.secondary)
            .overlay(
                Rectangle()
                    .stroke(
                        isTarget ? PixelPalette.accentDark : PixelPalette.line,
                        lineWidth: isTarget ? 2.4 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GuitarChordChoice: View {
    let chord: FPGAGuitarChord
    let isSelected: Bool
    let isTarget: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(chord.keyboardKey) \(chord.name)")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(isSelected ? PixelPalette.card : PixelPalette.ink)
                    .lineLimit(1)
                Text(chord.shortSummary)
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(isSelected ? PixelPalette.card : PixelPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? PixelPalette.accentDark : PixelPalette.secondary)
            .overlay(
                Rectangle()
                    .stroke(
                        isTarget ? PixelPalette.accent : PixelPalette.line,
                        lineWidth: isTarget ? 2.4 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
}