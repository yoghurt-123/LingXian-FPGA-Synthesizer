import SwiftUI

struct HomeView: View {
    let onOpenPerformance: () -> Void
    let onOpenGuitar: () -> Void
    let onOpenDrums: () -> Void
    let onOpenPiano: () -> Void
    let onOpenMusicHall: () -> Void
    let onOpenConcert: () -> Void
    let onOpenBluetooth: () -> Void
    let onOpenHelp: () -> Void
    @EnvironmentObject private var bluetooth: InstrumentBluetooth

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                header
                hero
                PaperSectionLabel(index: "02 / DESTINATIONS", title: "选择一张纸片")
                featureGrid
                footnote
                footer
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PaperOrbitMark(size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text("AURAL / 乐器手记")
                    .font(.system(size: 23, weight: .semibold, design: .serif))
                    .foregroundStyle(PaperPalette.ink)
                Text("INSTRUMENT LOG · LOCAL ONLY")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .tracking(1.2)
                    .foregroundStyle(PaperPalette.pencil)
            }

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                Circle()
                    .fill(bluetooth.isPerformanceSinkAvailable ? PaperPalette.green : PaperPalette.pencil)
                    .frame(width: 6, height: 6)
                Text(bluetooth.isPerformanceSinkAvailable ? "FPGA 音箱就绪" : (bluetooth.isReady ? "BLE 诊断连接" : "本地 · BLE 未连接"))
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(PaperPalette.inkSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(PaperPalette.paperWhite.opacity(0.72)))
            .overlay(Capsule().stroke(PaperPalette.line, lineWidth: 0.8))

            Text(AppInfo.versionLabel)
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PaperPalette.pencil)

            Button(action: onOpenBluetooth) {
                Text("连接设备")
            }
            .buttonStyle(PixelOutlineButtonStyle(fontSize: 10, horizontalPadding: 10, verticalPadding: 6))
        }
        .padding(.bottom, 2)
    }

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                heroCopy
                    .frame(maxWidth: 430, alignment: .leading)
                heroPrint
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 16) {
                heroCopy
                heroPrint
            }
        }
        .padding(.top, 6)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OBSERVATION 01 / PAPER ORBIT")
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .tracking(1.6)
                .foregroundStyle(PaperPalette.red)

            VStack(alignment: .leading, spacing: 0) {
                Text("在纸上，")
                (Text("听见") + Text("轨道").foregroundColor(PaperPalette.red) + Text("。"))
            }
            .font(.system(size: 52, weight: .regular, design: .serif))
            .foregroundStyle(PaperPalette.ink)
            .lineSpacing(-4)
            .fixedSize(horizontal: false, vertical: true)

            Text("钢琴、电吉他、九鼓与一台会公转的唱片机。\n不把音乐做成仪表盘，只把每一次触碰留在纸面上。")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(PaperPalette.inkSoft)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onOpenPerformance) {
                    Text("进入自由演奏  →")
                }
                .buttonStyle(PixelFilledButtonStyle(fontSize: 12, horizontalPadding: 14, verticalPadding: 9))
                Button(action: onOpenMusicHall) {
                    Text("打开音乐厅")
                }
                .buttonStyle(PixelOutlineButtonStyle(fontSize: 12, horizontalPadding: 14, verticalPadding: 9))
            }

            Text("触屏演奏 · 本地音色 · FPGA BLE 演出")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(PaperPalette.pencil)
        }
    }

    private var heroPrint: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PaperReferencePrint()
                    .frame(maxWidth: .infinity)
                    .frame(height: 278)
                    .clipped()
                HStack {
                    Text("PRINT / USER REFERENCE")
                    Spacer()
                    Text("GREY PAPER · ORBITS")
                }
                .font(.system(size: 7, weight: .medium, design: .serif))
                .tracking(0.8)
                .foregroundStyle(PaperPalette.pencil)
                .padding(.top, 8)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(PaperPalette.paperWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.9), lineWidth: 0.8)
            )
            .shadow(color: PaperPalette.shadow.opacity(0.55), radius: 12, y: 5)
            .rotationEffect(.degrees(-1.2))

            Rectangle()
                .fill(PaperPalette.paperDeep.opacity(0.72))
                .frame(width: 76, height: 18)
                .rotationEffect(.degrees(2))
                .offset(y: -8)

            Text("ARCHIVE\n2026\nNO. 01")
                .font(.system(size: 7, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(PaperPalette.redDeep)
                .padding(9)
                .background(Circle().fill(PaperPalette.paper.opacity(0.74)))
                .overlay(Circle().stroke(PaperPalette.red.opacity(0.42), lineWidth: 0.8))
                .rotationEffect(.degrees(8))
                .offset(x: 250, y: 268)
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            destinationCard(
                index: "00 / BLUETOOTH",
                title: "蓝牙连接",
                subtitle: "ESP 通讯 · 能力诊断 · 连接状态",
                tint: PaperPalette.green,
                symbol: "antenna.radiowaves.left.and.right",
                action: onOpenBluetooth
            )
            destinationCard(
                index: "01 / FREE PLAY",
                title: "自由演奏",
                subtitle: "钢琴 · 九鼓 · 吉他 · 表情面板",
                tint: PaperPalette.red,
                instrument: .piano,
                action: onOpenPerformance
            )
            destinationCard(
                index: "02 / ELECTRIC GUITAR",
                title: "电吉他音阶",
                subtitle: "空弦与品位 · 长按 · 真实触弦",
                tint: PaperPalette.red,
                instrument: .guitar,
                action: onOpenGuitar
            )
            destinationCard(
                index: "03 / DRUM KIT",
                title: "架子鼓音阶",
                subtitle: "九宫格 · 亮垫提示 · 独立反馈",
                tint: PaperPalette.green,
                instrument: .drums,
                action: onOpenDrums
            )
            destinationCard(
                index: "04 / PIANO GAME",
                title: "钢琴音游",
                subtitle: "C4–C5 · 长按与连击 · 纸面轨道",
                tint: PaperPalette.blue,
                instrument: .piano,
                action: onOpenPiano
            )
            destinationCard(
                index: "05 / MUSIC HALL",
                title: "音乐厅",
                subtitle: "曲库 · 大唱片 · 设备传输与演出",
                tint: PaperPalette.redDeep,
                symbol: "record.circle",
                action: onOpenMusicHall
            )
            destinationCard(
                index: "06 / PAPER STAGE",
                title: "纸上舞台",
                subtitle: "舞台曲线 · 曲目灯光 · 装饰演出",
                tint: PaperPalette.blue,
                symbol: "circle.hexagongrid",
                action: onOpenConcert
            )
            destinationCard(
                index: "07 / FIELD NOTES",
                title: "使用说明",
                subtitle: "操作 · 判定 · 当前硬件限制",
                tint: PaperPalette.inkSoft,
                symbol: "book.closed",
                action: onOpenHelp
            )
        }
    }

    private func destinationCard(
        index: String,
        title: String,
        subtitle: String,
        tint: Color,
        symbol: String? = nil,
        instrument: PaperInstrumentKind? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tint.opacity(0.78))
                            .frame(width: 6, height: 6)
                        Text(index)
                            .font(.system(size: 7, weight: .medium, design: .serif))
                            .tracking(0.8)
                            .foregroundStyle(PaperPalette.pencil)
                        Spacer(minLength: 0)
                    }
                    Text(title)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(PaperPalette.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .regular, design: .serif))
                        .foregroundStyle(PaperPalette.inkSoft)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)

                if let instrument {
                    PaperInstrumentArt(kind: instrument)
                        .frame(width: 96, height: 70)
                        .opacity(0.82)
                        .offset(x: 12, y: 8)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 38, weight: .ultraLight, design: .serif))
                        .foregroundStyle(tint.opacity(0.52))
                        .offset(x: 5, y: 3)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PaperPalette.pencil)
                    .padding(12)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PaperPalette.line.opacity(0.95), lineWidth: 0.8)
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PaperPalette.paperWhite.opacity(0.72))
            )
        }
        .buttonStyle(HomePaperButtonStyle())
    }

    private var footnote: some View {
        HStack(spacing: 14) {
            Text("纸面本身就是界面。")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(PaperPalette.ink)
            Text("去掉背景图后，纸片按钮、细灰线、手绘乐器插画和留白仍然成立。")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .foregroundStyle(PaperPalette.inkSoft)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(PaperPalette.red).frame(width: 6, height: 6)
                Circle().fill(PaperPalette.green).frame(width: 6, height: 6)
                Circle().fill(PaperPalette.blue).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(PaperPalette.line.opacity(0.8)).frame(height: 0.8)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PaperPalette.line.opacity(0.8)).frame(height: 0.8)
        }
    }

    private var footer: some View {
        HStack {
            Text("FPGA INSTRUMENT / IPAD LOCAL AUDIO")
            Spacer()
            Text("素材：用户参考图 · 本地生成线稿")
        }
        .font(.system(size: 8, weight: .regular, design: .serif))
        .tracking(0.7)
        .foregroundStyle(PaperPalette.pencil)
    }
}

private struct HomePaperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? PaperPalette.paperDeep.opacity(0.5) : Color.clear)
            )
            .shadow(color: PaperPalette.shadow.opacity(configuration.isPressed ? 0.1 : 0.28), radius: 5, y: 2)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
