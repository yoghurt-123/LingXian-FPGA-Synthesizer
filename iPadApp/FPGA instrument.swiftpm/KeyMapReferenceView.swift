import SwiftUI

struct KeyMapReferenceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FPGA 键位对照")
                        .font(.system(size: 26, weight: .heavy, design: .serif))
                        .foregroundStyle(PixelPalette.ink)
                    Text("当前 RTL：钢琴 A–L / Z–M · 吉他 QWERTY · 和弦 UIOP · 鼓小键盘 1–9 · 品位 0–12")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                    Text(FPGAKeyMap.sourceNote)
                        .font(.system(size: 9, weight: .regular, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                pianoSection
                guitarSection
                chordSection
                fretSection
                drumSection

                ForEach(FPGAKeyMap.controlGroups) { group in
                    controlGroup(group)
                }

                Text(FPGAKeyMap.localPreviewNote + " 高级表情键仅显示 FPGA 键位；自由演奏本地音频不处理弯音、颤音、滑音时间、过载和混响。")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PixelPanelBackground(fill: PixelPalette.secondary, cut: 6))
            }
            .padding(16)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(PixelPalette.background)
    }

    private var pianoSection: some View {
        referenceCard(title: "钢琴 · 16 键", subtitle: "白键 A S D F G H J K L · 黑键 Z X C V B N M") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                ForEach(FPGAKeyMap.pianoKeys) { key in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(key.keyboardKey)
                                .font(.system(size: 13, weight: .heavy, design: .serif))
                                .foregroundStyle(key.isBlack ? PixelPalette.card : PixelPalette.ink)
                                .frame(minWidth: 22)
                                .padding(.vertical, 2)
                                .background(key.isBlack ? PixelPalette.ink : PixelPalette.secondary)
                            Text(key.noteName)
                                .font(.system(size: 11, weight: .bold, design: .serif))
                                .foregroundStyle(PixelPalette.ink)
                        }
                        Text(key.isBlack ? "黑键" : "白键")
                            .font(.system(size: 8, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .background(PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line.opacity(0.5), lineWidth: 0.8))
                }
            }
        }
    }

    private var guitarSection: some View {
        referenceCard(title: "电吉他 · 六弦", subtitle: "显示从上到下为 6→1 弦；键位 Q W E R T Y") {
            VStack(spacing: 4) {
                ForEach(FPGAKeyMap.guitarStrings) { string in
                    HStack(spacing: 8) {
                        Text(string.keyboardKey)
                            .font(.system(size: 12, weight: .heavy, design: .serif))
                            .foregroundStyle(PixelPalette.accentDark)
                            .frame(width: 24)
                        Text("\(string.stringNumber)弦")
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text(string.noteName)
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Spacer(minLength: 6)
                        Text("空弦")
                            .font(.system(size: 9, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line.opacity(0.5), lineWidth: 0.8))
                }
            }
        }
    }

    private var chordSection: some View {
        referenceCard(title: "和弦 · U I O P", subtitle: "U=C · I=G · O=Dm · P=Am；按下即三音齐奏") {
            VStack(spacing: 4) {
                ForEach(FPGAKeyMap.guitarChords) { chord in
                    HStack(spacing: 8) {
                        Text(chord.keyboardKey)
                            .font(.system(size: 12, weight: .heavy, design: .serif))
                            .foregroundStyle(PixelPalette.accentDark)
                            .frame(width: 24)
                        Text(chord.name)
                            .font(.system(size: 12, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                            .frame(width: 42, alignment: .leading)
                        Text(chord.summary)
                            .font(.system(size: 9, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line.opacity(0.5), lineWidth: 0.8))
                }
            }
        }
    }

    private var fretSection: some View {
        referenceCard(title: "吉他品位 · 0–12", subtitle: "主键 1–9、0、-、=、Backspace；不是六个品位") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(FPGAKeyMap.frets) { item in
                    VStack(spacing: 1) {
                        Text("\(item.fret)")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text(item.compactKey)
                            .font(.system(size: 9, weight: .semibold, design: .serif))
                            .foregroundStyle(PixelPalette.accentDark)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line.opacity(0.5), lineWidth: 0.8))
                }
            }
        }
    }

    private var drumSection: some View {
        referenceCard(title: "九鼓 · 小键盘 1–9", subtitle: "不要与主键数字混淆；九宫格位置与自由演奏一致") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(FPGAKeyMap.drumPads.sorted { $0.gridIndex < $1.gridIndex }) { pad in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("小键盘\(pad.keypadNumber)")
                            .font(.system(size: 9, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.accentDark)
                        Text(pad.instrument.displayName)
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                        Text("\(pad.instrument.shortLabel) · \(pad.instrument.isCymbalLike ? "镲片" : "鼓")")
                            .font(.system(size: 8, weight: .medium, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .background(PixelPalette.card)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line.opacity(0.5), lineWidth: 0.8))
                }
            }
        }
    }

    private func controlGroup(_ group: FPGAControlGroup) -> some View {
        referenceCard(title: group.title, subtitle: group.id == "tone" ? "音量与停止可在本地演示；高级音色/表情仅键位参考" : "按键名称来自当前 FPGA RTL") {
            VStack(spacing: 3) {
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.ink)
                            .frame(width: 114, alignment: .leading)
                        Text(row.key)
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(PixelPalette.accentDark)
                            .frame(width: 128, alignment: .leading)
                        Text(row.detail)
                            .font(.system(size: 9, weight: .regular, design: .serif))
                            .foregroundStyle(PixelPalette.muted)
                        Spacer(minLength: 2)
                        Text(row.localPreview)
                            .font(.system(size: 8, weight: .semibold, design: .serif))
                            .foregroundStyle(row.localPreview == "仅键位参考" || row.localPreview == "未接入本地" ? PixelPalette.muted : PixelPalette.good)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(PixelPalette.card)
                }
            }
        }
    }

    private func referenceCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 6))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }
}

struct KeyMapReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KeyMapReferenceView()
                .navigationTitle("FPGA 键位对照")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}