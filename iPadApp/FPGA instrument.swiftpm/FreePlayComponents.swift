import SwiftUI

struct FreeSectionHeader: View {
    let title: String
    let detail: String
    let trailing: String
    var art: PaperInstrumentKind? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let art {
                PaperInstrumentArt(kind: art)
                    .frame(width: 28, height: 16)
                    .opacity(0.90)
            }
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 3)
            Text(trailing)
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(height: 16)
    }
}

struct FreeVelocitySelector: View {
    @Binding var level: Int
    @Binding var accent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text("力度")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            ForEach(0..<3, id: \.self) { index in
                let item = FPGAKeyMap.velocityCodes[index]
                Button {
                    level = index
                } label: {
                    Text("\(item.name)\(item.code)")
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .foregroundStyle(level == index ? PixelPalette.card : PixelPalette.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(level == index ? PixelPalette.accent : PixelPalette.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            Button {
                accent.toggle()
            } label: {
                Text("重音")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(accent ? PixelPalette.card : PixelPalette.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(accent ? PixelPalette.accentDark : PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            Text("F1/F2 · 左Shift")
                .font(.system(size: 7, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .lineLimit(1)
        }
    }
}

struct FreeDrumGrid: View {
    @Binding var pressedIDs: Set<Int>
    let onTouchDown: (FPGADrumPad, Int) -> Void
    let onTouchUp: (Int, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 5
            let width: CGFloat = max(1, proxy.size.width)
            let height: CGFloat = max(1, proxy.size.height)
            let cellWidth: CGFloat = max(1, (width - gap * 2) / 3)
            let cellHeight: CGFloat = max(1, (height - gap * 2) / 3)
            let pads: [FPGADrumPad] = FPGAKeyMap.drumPads.sorted { $0.gridIndex < $1.gridIndex }

            ZStack(alignment: .topLeading) {
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { column in
                                let index: Int = row * 3 + column
                                if pads.indices.contains(index) {
                                    FreeDrumPadCard(
                                        pad: pads[index],
                                        isPressed: pressedIDs.contains(pads[index].id)
                                    )
                                    .frame(width: cellWidth, height: cellHeight)
                                }
                            }
                        }
                    }
                }

                MultiTouchOverlay(
                    regions: drumRegions(cellWidth: cellWidth, cellHeight: cellHeight, gap: gap),
                    onBegan: { token, id in
                        guard let pad = pads.first(where: { $0.id == id }) else { return }
                        pressedIDs.insert(id)
                        onTouchDown(pad, token)
                    },
                    onMoved: { _, oldID, _ in
                        pressedIDs.remove(oldID)
                    },
                    onEnded: { token, id, cancelled in
                        pressedIDs.remove(id)
                        onTouchUp(token, cancelled)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func drumRegions(cellWidth: CGFloat, cellHeight: CGFloat, gap: CGFloat) -> [TouchRegion] {
        var result: [TouchRegion] = []
        for pad in FPGAKeyMap.drumPads {
            let x: CGFloat = CGFloat(pad.gridColumn) * (cellWidth + gap)
            let y: CGFloat = CGFloat(pad.gridRow) * (cellHeight + gap)
            result.append(
                TouchRegion(
                    id: pad.id,
                    rect: CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                )
            )
        }
        return result
    }
}

private struct FreeDrumPadCard: View {
    let pad: FPGADrumPad
    let isPressed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                FreeDrumGlyph(instrument: pad.instrument)
                Text("小键盘\(pad.keypadNumber)")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(pad.instrument.displayName)
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(PixelPanelBackground(fill: isPressed ? PixelPalette.secondary : PixelPalette.card, cut: 6))
        .overlay(
            PixelPanelShape(cut: 6)
                .stroke(isPressed ? PixelPalette.accent : PixelPalette.line, lineWidth: isPressed ? 2 : 1)
        )
    }
}

private struct FreeDrumGlyph: View {
    let instrument: DrumKitInstrument

    var body: some View {
        ZStack {
            if instrument.isCymbalLike {
                Ellipse()
                    .fill(PixelPalette.accent)
                    .frame(width: 24, height: 7)
                    .overlay(Ellipse().stroke(PixelPalette.ink, lineWidth: 0.8))
                Rectangle()
                    .fill(PixelPalette.ink)
                    .frame(width: 1.5, height: 9)
                    .offset(y: 7)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(PixelPalette.accentDark)
                    .frame(width: 24, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(PixelPalette.ink, lineWidth: 0.8))
                Ellipse()
                    .fill(PixelPalette.card)
                    .frame(width: 22, height: 5)
                    .overlay(Ellipse().stroke(PixelPalette.ink, lineWidth: 0.6))
            }
        }
        .frame(width: 26, height: 18)
    }
}

struct FreeGuitarLeftPanel: View {
    @Binding var selectedFret: Int
    @Binding var selectedChordID: Int?
    let hardwareMode: Bool
    let fretAvailable: Bool
    let chordAvailable: Bool
    let onFret: (Int) -> Void
    let onChord: (FPGAGuitarChord) -> Void

    private let firstFrets: [FPGAFretKey] = Array(FPGAKeyMap.frets.prefix(7))
    private let secondFrets: [FPGAFretKey] = Array(FPGAKeyMap.frets.dropFirst(7))

    private var currentLabel: String {
        if hardwareMode && !fretAvailable && !chordAvailable { return "硬件默认" }
        if let id = selectedChordID, chordAvailable {
            return FPGAKeyMap.guitarChords.first { $0.id == id }?.name ?? "和弦"
        }
        return fretAvailable ? "\(selectedFret)品" : "硬件默认"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("左手")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text(currentLabel)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                Spacer(minLength: 0)
                Text("0–12品")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
            }

            if hardwareMode && (!fretAvailable || !chordAvailable) {
                Text("FPGA 未声明\(!fretAvailable ? "品位" : "")\(!fretAvailable && !chordAvailable ? " / " : "")\(!chordAvailable ? "和弦" : "")能力；对应控件禁用")
                    .font(.system(size: 8, weight: .semibold, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 3) {
                ForEach(firstFrets) { item in
                    FreeFretCell(
                        item: item,
                        selected: selectedFret == item.fret && selectedChordID == nil
                    ) {
                        onFret(item.fret)
                    }
                }
            }
            .disabled(!fretAvailable)
            .opacity(fretAvailable ? 1 : 0.42)
            HStack(spacing: 3) {
                ForEach(secondFrets) { item in
                    FreeFretCell(
                        item: item,
                        selected: selectedFret == item.fret && selectedChordID == nil
                    ) {
                        onFret(item.fret)
                    }
                }
                Spacer(minLength: 0)
            }
            .disabled(!fretAvailable)
            .opacity(fretAvailable ? 1 : 0.42)

            HStack(spacing: 3) {
                ForEach(FPGAKeyMap.guitarChords) { chord in
                    Button {
                        onChord(chord)
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(chord.keyboardKey) \(chord.name)")
                                .font(.system(size: 10, weight: .bold, design: .serif))
                                .foregroundStyle(selectedChordID == chord.id ? PixelPalette.card : PixelPalette.ink)
                            Text(chord.shortSummary)
                                .font(.system(size: 8, weight: .medium, design: .serif))
                                .foregroundStyle(selectedChordID == chord.id ? PixelPalette.card : PixelPalette.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(selectedChordID == chord.id ? PixelPalette.accentDark : PixelPalette.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(!chordAvailable)
            .opacity(chordAvailable ? 1 : 0.42)

            Text(fretAvailable ? "品位改变下一次拨弦；滑音开启时作用于当前主奏，不重复拨弦" : "FPGA 当前未开放品位/和弦；六弦触发使用硬件默认状态")
                .font(.system(size: 7, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct FreeFretCell: View {
    let item: FPGAFretKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(item.fret)")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(selected ? PixelPalette.card : PixelPalette.ink)
                Text(item.compactKey)
                    .font(.system(size: 8, weight: .semibold, design: .serif))
                    .foregroundStyle(selected ? PixelPalette.card : PixelPalette.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(selected ? PixelPalette.accent : PixelPalette.secondary)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(selected ? PixelPalette.accentDark : PixelPalette.line, lineWidth: selected ? 1.6 : 0.8))
        }
        .buttonStyle(.plain)
    }
}

struct FreeStringBoard: View {
    let selectedFret: Int
    let hardwarePitchState: Bool
    @Binding var pressedIndices: Set<Int>
    let onTouchDown: (FPGAGuitarString, Int) -> Void
    let onTouchUp: (Int, PerformanceReleaseReason) -> Void

    var body: some View {
        GeometryReader { proxy in
            let rows: Int = FPGAKeyMap.guitarStrings.count
            let gap: CGFloat = 4
            let rowHeight: CGFloat = max(24, (proxy.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            let rowWidth: CGFloat = proxy.size.width

            ZStack(alignment: .topLeading) {
                VStack(spacing: gap) {
                    ForEach(FPGAKeyMap.guitarStrings.indices, id: \.self) { index in
                        let string = FPGAKeyMap.guitarStrings[index]
                        FreeStringRow(
                            string: string,
                            selectedFret: selectedFret,
                            hardwarePitchState: hardwarePitchState,
                            isPressed: pressedIndices.contains(index)
                        )
                        .frame(width: rowWidth, height: rowHeight)
                    }
                }

                MultiTouchOverlay(
                    regions: stringRegions(rowHeight: rowHeight, gap: gap, width: rowWidth),
                    onBegan: { token, id in
                        guard FPGAKeyMap.guitarStrings.indices.contains(id) else { return }
                        pressedIndices.insert(id)
                        onTouchDown(FPGAKeyMap.guitarStrings[id], token)
                    },
                    onMoved: { token, oldID, _ in
                        pressedIndices.remove(oldID)
                        onTouchUp(token, .slideOut)
                    },
                    onEnded: { token, id, cancelled in
                        pressedIndices.remove(id)
                        onTouchUp(token, cancelled ? .cancel : .release)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func stringRegions(rowHeight: CGFloat, gap: CGFloat, width: CGFloat) -> [TouchRegion] {
        var result: [TouchRegion] = []
        for index in 0..<6 {
            let y: CGFloat = CGFloat(index) * (rowHeight + gap)
            result.append(
                TouchRegion(
                    id: index,
                    rect: CGRect(x: 0, y: y, width: width, height: rowHeight)
                )
            )
        }
        return result
    }
}

private struct FreeStringRow: View {
    let string: FPGAGuitarString
    let selectedFret: Int
    let hardwarePitchState: Bool
    let isPressed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(string.keyboardKey)
                .font(.system(size: 12, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(string.stringNumber)弦")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text(string.noteName)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
            }
            .frame(width: 38, alignment: .leading)

            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPressed ? PixelPalette.secondary : PixelPalette.card)
                Rectangle()
                    .fill(PixelPalette.ink)
                    .frame(height: string.stringNumber <= 2 ? 2.2 : (string.stringNumber >= 5 ? 1.2 : 1.7))
                    .padding(.horizontal, 8)
                Text(hardwarePitchState ? "硬件音高" : (selectedFret == 0 ? "空弦" : "\(selectedFret)品"))
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                    .padding(.trailing, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isPressed ? PixelPalette.accent : PixelPalette.line, lineWidth: isPressed ? 2 : 1)
            )
        }
        .padding(.horizontal, 4)
    }
}

struct FreeOctaveSelector: View {
    @Binding var octave: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("八度")
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            ForEach(0..<3, id: \.self) { value in
                Button {
                    octave = value
                } label: {
                    Text(value == 0 ? "低" : value == 2 ? "高" : "原")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundStyle(octave == value ? PixelPalette.card : PixelPalette.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(octave == value ? PixelPalette.accent : PixelPalette.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            Text("Home/End")
                .font(.system(size: 7, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
        }
    }
}

struct FreePianoKeyboard: View {
    @Binding var pressedIDs: Set<Int>
    let onTouchDown: (FPGAPianoKey, Int) -> Void
    let onTouchUp: (Int, PerformanceReleaseReason) -> Void
    let onTouchMoved: (Int, FPGAPianoKey?, FPGAPianoKey?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let whiteKeys: [FPGAPianoKey] = FPGAKeyMap.whitePianoKeys
            let blackKeys: [FPGAPianoKey] = FPGAKeyMap.blackPianoKeys
            let whiteWidth: CGFloat = max(
                1,
                (proxy.size.width - gap * CGFloat(whiteKeys.count - 1)) / CGFloat(whiteKeys.count)
            )
            let blackWidth: CGFloat = whiteWidth * 0.64
            let blackHeight: CGFloat = proxy.size.height * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(whiteKeys.indices, id: \.self) { index in
                    let key = whiteKeys[index]
                    FreeWhiteKey(key: key, isPressed: pressedIDs.contains(key.id))
                        .frame(width: whiteWidth, height: proxy.size.height)
                        .offset(x: CGFloat(index) * (whiteWidth + gap), y: 0)
                }

                ForEach(blackKeys) { key in
                    let x: CGFloat = blackX(
                        key: key,
                        whiteWidth: whiteWidth,
                        blackWidth: blackWidth,
                        gap: gap,
                        totalWidth: proxy.size.width
                    )
                    FreeBlackKey(key: key, isPressed: pressedIDs.contains(key.id))
                        .frame(width: blackWidth, height: blackHeight)
                        .offset(x: x, y: 0)
                }

                MultiTouchOverlay(
                    regions: pianoRegions(
                        whiteKeys: whiteKeys,
                        blackKeys: blackKeys,
                        whiteWidth: whiteWidth,
                        blackWidth: blackWidth,
                        blackHeight: blackHeight,
                        gap: gap,
                        totalWidth: proxy.size.width,
                        totalHeight: proxy.size.height
                    ),
                    onBegan: { token, id in
                        guard let key = FPGAKeyMap.pianoKeys.first(where: { $0.id == id }) else { return }
                        pressedIDs.insert(id)
                        onTouchDown(key, token)
                    },
                    onMoved: { token, oldID, newID in
                        let oldKey = FPGAKeyMap.pianoKeys.first(where: { $0.id == oldID })
                        let newKey = newID.flatMap { newID in
                            FPGAKeyMap.pianoKeys.first(where: { $0.id == newID })
                        }
                        pressedIDs.remove(oldID)
                        if let newKey {
                            pressedIDs.insert(newKey.id)
                        }
                        onTouchMoved(token, oldKey, newKey)
                    },
                    onEnded: { token, id, cancelled in
                        pressedIDs.remove(id)
                        onTouchUp(token, cancelled ? .cancel : .release)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func blackX(
        key: FPGAPianoKey,
        whiteWidth: CGFloat,
        blackWidth: CGFloat,
        gap: CGFloat,
        totalWidth: CGFloat
    ) -> CGFloat {
        guard let after = key.blackAfterWhite else { return 0 }
        let boundary: CGFloat = CGFloat(after + 1) * (whiteWidth + gap) - gap * 0.5
        let raw: CGFloat = boundary - blackWidth * 0.5
        return min(max(raw, 0), max(0, totalWidth - blackWidth))
    }

    private func pianoRegions(
        whiteKeys: [FPGAPianoKey],
        blackKeys: [FPGAPianoKey],
        whiteWidth: CGFloat,
        blackWidth: CGFloat,
        blackHeight: CGFloat,
        gap: CGFloat,
        totalWidth: CGFloat,
        totalHeight: CGFloat
    ) -> [TouchRegion] {
        var result: [TouchRegion] = []
        for key in blackKeys {
            let x: CGFloat = blackX(
                key: key,
                whiteWidth: whiteWidth,
                blackWidth: blackWidth,
                gap: gap,
                totalWidth: totalWidth
            )
            result.append(
                TouchRegion(
                    id: key.id,
                    rect: CGRect(x: x, y: 0, width: blackWidth, height: blackHeight)
                )
            )
        }
        for (index, key) in whiteKeys.enumerated() {
            result.append(
                TouchRegion(
                    id: key.id,
                    rect: CGRect(
                        x: CGFloat(index) * (whiteWidth + gap),
                        y: 0,
                        width: whiteWidth,
                        height: totalHeight
                    )
                )
            )
        }
        return result
    }
}

private struct FreeWhiteKey: View {
    let key: FPGAPianoKey
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isPressed ? PixelPalette.secondary : PixelPalette.card)
            RoundedRectangle(cornerRadius: 3)
                .stroke(PixelPalette.line, lineWidth: 1)
            VStack(spacing: 0) {
                Text(key.keyboardKey)
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text(key.noteName)
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
            }
            .padding(.bottom, 4)
        }
    }
}

private struct FreeBlackKey: View {
    let key: FPGAPianoKey
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isPressed ? PixelPalette.accent : PixelPalette.ink)
            RoundedRectangle(cornerRadius: 2)
                .stroke(PixelPalette.ink, lineWidth: 1)
            VStack(spacing: 0) {
                Text(key.keyboardKey)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.card)
                Text(key.noteName)
                    .font(.system(size: 6, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.secondary)
            }
            .padding(.bottom, 3)
        }
    }
}
