import SwiftUI

struct PerformanceView: View {
    @ObservedObject var audio: FreePlayAudio
    @ObservedObject var router: FreePlayEventRouter
    @EnvironmentObject private var bluetooth: InstrumentBluetooth
    @Environment(\.scenePhase) private var scenePhase

    @State private var masterVolume: Double = 0.80
    @State private var velocityLevel: Int = 1
    @State private var accent: Bool = false
    @State private var selectedChordID: Int? = nil
    @State private var pressedDrums: Set<Int> = []
    @State private var pressedStrings: Set<Int> = []
    @State private var pressedPianos: Set<Int> = []
    @State private var lastAction: String = "点击任意发声键开始"
    @State private var hitCount: Int = 0
    @State private var showKeyMap: Bool = false
    @State private var showExpression: Bool = false

    private var velocityCode: Int {
        let base: Int = [8, 11, 15][min(max(velocityLevel, 0), 2)]
        return min(15, base + (accent ? 2 : 0))
    }

    private var selectedChord: FPGAGuitarChord? {
        guard let id = selectedChordID else { return nil }
        return FPGAKeyMap.guitarChords.first { $0.id == id }
    }

    private var octaveBinding: Binding<Int> {
        Binding(
            get: { router.octave },
            set: { router.setOctave($0) }
        )
    }

    private var fretBinding: Binding<Int> {
        Binding(
            get: { router.fret },
            set: { router.setFret($0) }
        )
    }

    private var octaveLabel: String {
        if router.isHardwareMode {
            guard router.supports(.pianoOctave) else { return "FPGA 未声明八度" }
            return "FPGA八度目标：\(octaveTitle(router.octave))"
        }
        switch router.octave {
        case 0: return "当前：低八度"
        case 2: return "当前：高八度"
        default: return "当前：原八度"
        }
    }

    private var guitarFretAvailable: Bool {
        !router.isHardwareMode || router.supports(.guitarFret)
    }

    private var guitarChordAvailable: Bool {
        !router.isHardwareMode || router.supports(.chords)
    }

    private var drumAvailable: Bool {
        !router.isHardwareMode || router.supports(.drums)
    }

    private var guitarPluckAvailable: Bool {
        !router.isHardwareMode || router.supports(.guitarPluck)
    }

    private var pianoAvailable: Bool {
        !router.isHardwareMode || router.supports(.piano)
    }

    private var modeSelector: some View {
        HStack(spacing: 3) {
            ForEach(PerformanceMode.allCases) { option in
                Button {
                    switchMode(option)
                } label: {
                    Text(option.title)
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .foregroundStyle(router.mode == option ? PixelPalette.card : PixelPalette.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(router.mode == option ? PixelPalette.accentDark : PixelPalette.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(option == .bleInstrument && !bluetooth.isPerformanceSinkAvailable)
                .opacity(option == .bleInstrument && !bluetooth.isPerformanceSinkAvailable ? 0.45 : 1)
            }
        }
    }

    private var modeStatusText: String {
        if router.isHardwareMode {
            return "FPGA音箱 · 本地发声关闭 · \(router.protocolLabel)"
        }
        if bluetooth.isPerformanceSinkAvailable {
            return "iPad本地声音 · 可切换 FPGA音箱"
        }
        return bluetooth.isReady ? "iPad本地声音 · BLE 诊断连接 · 演奏协议未就位" : "iPad本地声音 · BLE 未连接"
    }

    var body: some View {
        GeometryReader { proxy in
            let height: CGFloat = proxy.size.height
            let panelHeight: CGFloat = showExpression ? 104 : 0
            let sectionBudget: CGFloat = max(380, height - panelHeight - 120)
            let drumHeight: CGFloat = max(126, min(190, sectionBudget * 0.28))
            let guitarHeight: CGFloat = max(170, min(260, sectionBudget * 0.44))
            let pianoHeight: CGFloat = max(98, min(150, sectionBudget * 0.22))

            VStack(spacing: 7) {
                topBar
                if showExpression {
                    FreePlayExpressionPanel(router: router)
                        .frame(height: panelHeight)
                }
                drumSection
                    .frame(height: drumHeight)
                guitarSection
                    .frame(height: guitarHeight)
                pianoSection
                    .frame(height: pianoHeight)
                footer
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .onAppear {
            router.attach(audio: audio, sink: bluetooth)
            if router.mode == .bleInstrument && !bluetooth.isPerformanceSinkAvailable {
                _ = router.setMode(.localDemo)
            }
            if router.isHardwareMode {
                router.resumeHardwareSession()
            } else {
                audio.prepare()
                audio.setMasterVolume(masterVolume)
            }
        }
        .onDisappear {
            router.allNotesOff(reason: .leavePage)
            audio.stopAll()
        }
        .onChange(of: masterVolume) { _, value in
            audio.setMasterVolume(value)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                router.allNotesOff(reason: .background)
            } else if router.isHardwareMode {
                if bluetooth.isPerformanceSinkAvailable {
                    router.resumeHardwareSession()
                } else {
                    _ = router.setMode(.localDemo)
                    audio.prepare()
                    audio.setMasterVolume(masterVolume)
                }
            }
        }
        .onChange(of: bluetooth.performanceReady) { _, ready in
            if ready {
                if router.isHardwareMode {
                    router.resumeHardwareSession()
                }
            } else if router.isHardwareMode {
                if bluetooth.isReady {
                    bluetooth.sendLinkLevelReleaseAll()
                    router.handleCapabilityLost()
                } else {
                    router.handleDisconnect()
                }
            }
        }
        .onChange(of: bluetooth.isReady) { _, ready in
            if !ready && router.isHardwareMode {
                router.handleDisconnect()
            }
        }
        .sheet(isPresented: $showKeyMap) {
            KeyMapReferenceSheet()
        }
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            modeSelector
            Text(modeStatusText)
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .foregroundStyle(router.isHardwareMode ? PixelPalette.good : PixelPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            FreeVelocitySelector(level: $velocityLevel, accent: $accent)

            Spacer(minLength: 3)

            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                Text(router.isHardwareMode ? "本地音量" : "总音量")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Slider(value: $masterVolume, in: 0...1)
                    .tint(PixelPalette.accent)
                    .frame(width: 88)
                    .disabled(router.isHardwareMode)
                    .opacity(router.isHardwareMode ? 0.45 : 1)
                Text("\(Int(masterVolume * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                    .frame(width: 28, alignment: .trailing)
                Text(router.isHardwareMode ? "硬件无命令" : "F8/F9")
                    .font(.system(size: 7, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(1)
            }

            Button {
                showExpression.toggle()
            } label: {
                Label("表情", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(
                PixelOutlineButtonStyle(
                    fontSize: 10,
                    horizontalPadding: 7,
                    verticalPadding: 5
                )
            )
            .disabled(!router.isHardwareMode)
            .opacity(router.isHardwareMode ? 1 : 0.45)

            Button(action: stopAll) {
                Label("全部停止 Esc", systemImage: "stop.fill")
            }
            .buttonStyle(
                PixelFilledButtonStyle(
                    fontSize: 10,
                    horizontalPadding: 7,
                    verticalPadding: 5,
                    fill: PixelPalette.miss,
                    foreground: PixelPalette.card,
                    border: PixelPalette.miss
                )
            )

            Button(action: { showKeyMap = true }) {
                Label("键位", systemImage: "keyboard")
            }
            .buttonStyle(
                PixelOutlineButtonStyle(
                    fontSize: 10,
                    horizontalPadding: 7,
                    verticalPadding: 5
                )
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 6))
        .overlay(PixelPanelShape(cut: 6).stroke(PixelPalette.line, lineWidth: 1))
    }

    private var drumSection: some View {
        VStack(spacing: 4) {
            FreeSectionHeader(
                title: "九鼓",
                detail: "小键盘 1–9 · 九宫格 · 多点触控",
                trailing: "最近：\(lastAction)", art: .drums
            )
            FreeDrumGrid(
                pressedIDs: $pressedDrums,
                onTouchDown: { pad, token in
                    hitCount += 1
                    lastAction = "小键盘\(pad.keypadNumber) \(pad.instrument.displayName)"
                    router.drumHit(
                        token: UInt32(clamping: token),
                        pad: pad.id,
                        velocity: velocityCode
                    )
                },
                onTouchUp: { _, _ in }
            )
            .disabled(!drumAvailable)
            .opacity(drumAvailable ? 1 : 0.45)
        }
        .padding(7)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 8))
        .overlay(PixelPanelShape(cut: 8).stroke(PixelPalette.line, lineWidth: 1.2))
    }

    private var guitarSection: some View {
        VStack(spacing: 4) {
            FreeSectionHeader(
                title: "电吉他",
                detail: "六弦 Q W E R T Y · 和弦 U I O P · 品位 0–12",
                trailing: selectedChord != nil ? "当前：\(selectedChord?.name ?? "和弦")" : "当前：\(router.fret)品", art: .guitar
            )

            GeometryReader { proxy in
                let leftWidth: CGFloat = max(315, min(395, proxy.size.width * 0.37))
                HStack(spacing: 7) {
                    FreeGuitarLeftPanel(
                        selectedFret: fretBinding,
                        selectedChordID: $selectedChordID,
                        hardwareMode: router.isHardwareMode,
                        fretAvailable: guitarFretAvailable,
                        chordAvailable: guitarChordAvailable,
                        onFret: { fret in
                            selectedChordID = nil
                            router.setFret(fret)
                            lastAction = "左手目标 \(fret)品"
                        },
                        onChord: { chord in
                            selectedChordID = chord.id
                            hitCount += 1
                            lastAction = "和弦 \(chord.name) · 短促触发，松手不制音"
                            router.chordTrigger(chordID: chord.id, velocity: velocityCode)
                        }
                    )
                    .frame(width: leftWidth)

                    FreeStringBoard(
                        selectedFret: router.fret,
                        hardwarePitchState: router.isHardwareMode && !router.supports(.guitarFret),
                        pressedIndices: $pressedStrings,
                        onTouchDown: { string, token in
                            hitCount += 1
                            lastAction = "\(string.displayTitle) · \(router.fret == 0 ? "空弦" : "\(router.fret)品")"
                            router.stringDown(
                                token: UInt32(clamping: token),
                                stringIndex: string.id,
                                fret: router.fret,
                                midiNote: string.openMIDINote + router.fret,
                                velocity: velocityCode
                            )
                        },
                        onTouchUp: { token, reason in
                            router.stringUp(token: UInt32(clamping: token), reason: reason)
                        }
                    )
                    .disabled(!guitarPluckAvailable)
                    .opacity(guitarPluckAvailable ? 1 : 0.45)
                }
            }

            HStack(spacing: 5) {
                Text("FPGA v2 支持：品位、掌根闷音、弯音端点、颤音、滑音/滑时、过载、混响；共享效果不回报当前值。")
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                Button(showExpression ? "收起表情" : "展开表情") { showExpression.toggle() }
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .buttonStyle(.plain)
                    .foregroundStyle(router.isHardwareMode ? PixelPalette.accentDark : PixelPalette.muted)
                    .disabled(!router.isHardwareMode)
            }
        }
        .padding(7)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 8))
        .overlay(PixelPanelShape(cut: 8).stroke(PixelPalette.line, lineWidth: 1.2))
    }

    private var pianoSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                FreeSectionHeader(
                    title: "钢琴",
                    detail: "白键 A–L · 黑键 Z–M · 字母不被黑键遮挡",
                    trailing: octaveLabel, art: .piano
                )
                FreeOctaveSelector(octave: octaveBinding)
                    .disabled(router.isHardwareMode && !router.supports(.pianoOctave))
                    .opacity(router.isHardwareMode && !router.supports(.pianoOctave) ? 0.42 : 1)
            }

            FreePianoKeyboard(
                pressedIDs: $pressedPianos,
                onTouchDown: { key, token in
                    hitCount += 1
                    lastAction = "钢琴 \(key.noteName) · \(key.keyboardKey)"
                    router.pianoDown(
                        token: UInt32(clamping: token),
                        keyID: key.id,
                        midiNote: key.midiNote + (router.octave - 1) * 12,
                        velocity: velocityCode
                    )
                },
                onTouchUp: { token, reason in
                    router.pianoUp(token: UInt32(clamping: token), reason: reason)
                },
                onTouchMoved: { token, oldKey, newKey in
                    if let newKey {
                        router.pianoMoved(
                            token: UInt32(clamping: token),
                            fromKey: oldKey?.id ?? -1,
                            toKey: newKey.id,
                            midiNote: newKey.midiNote + (router.octave - 1) * 12,
                            velocity: velocityCode
                        )
                    } else {
                        router.pianoUp(token: UInt32(clamping: token), reason: .slideOut)
                    }
                }
            )
            .disabled(!pianoAvailable)
            .opacity(pianoAvailable ? 1 : 0.45)
        }
        .padding(7)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 8))
        .overlay(PixelPanelShape(cut: 8).stroke(PixelPalette.line, lineWidth: 1.2))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
            Text(footerText)
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundStyle(router.lastFailure.isEmpty ? PixelPalette.muted : PixelPalette.miss)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            Text("已击打 \(hitCount)")
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
        }
    }

    private var footerText: String {
        if !router.lastFailure.isEmpty {
            return router.lastFailure
        }
        if router.isHardwareMode {
            if router.capabilities?.isV1 == true {
                return "FPGA协议 v1：钢琴/九鼓/吉他基础；品位、和弦、八度、表情和踏板未声明。"
            }
            return "FPGA协议 v2：App目标已发送；CAPS不回报效果当前值，共享过载/混响显示未确认。"
        }
        return "iPad本地声音：\(router.lastEventText)；硬件表情需切换 FPGA音箱。"
    }

    private func switchMode(_ option: PerformanceMode) {
        guard option != router.mode else { return }
        let previous = router.mode
        if !router.setMode(option) {
            lastAction = router.lastFailure
            return
        }
        pressedDrums.removeAll()
        pressedStrings.removeAll()
        pressedPianos.removeAll()
        selectedChordID = nil
        lastAction = "模式：\(previous.title) → \(option.title)"
        if option == .localDemo {
            audio.prepare()
            audio.setMasterVolume(masterVolume)
        }
    }

    private func stopAll() {
        router.allNotesOff(reason: .panic)
        pressedDrums.removeAll()
        pressedStrings.removeAll()
        pressedPianos.removeAll()
        selectedChordID = nil
        lastAction = "全部停止 (Esc)"
    }

    private func octaveTitle(_ value: Int) -> String {
        switch value {
        case 0: return "低"
        case 2: return "高"
        default: return "原"
        }
    }
}
