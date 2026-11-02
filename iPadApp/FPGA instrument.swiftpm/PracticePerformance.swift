import Foundation
import Combine
import SwiftUI

struct PracticeGuitarState {
    let fret: Int
    let chordID: Int?
}

enum PracticeGameKind: String, CaseIterable, Identifiable, Equatable {
    case piano
    case guitar
    case drums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .piano: return "钢琴音游"
        case .guitar: return "吉他音游"
        case .drums: return "架子鼓音游"
        }
    }

    func isPlayable(with capabilities: PerformanceCapabilities) -> Bool {
        guard capabilities.isReady else { return false }
        switch self {
        case .piano:
            return capabilities.supports(.piano)
        case .guitar:
            return capabilities.supports(.guitarPluck)
                && capabilities.supports(.guitarFret)
                && capabilities.supports(.chords)
        case .drums:
            return capabilities.supports(.drums)
        }
    }

    func missingControls(with capabilities: PerformanceCapabilities) -> [String] {
        switch self {
        case .piano:
            return capabilities.supports(.piano) ? [] : ["钢琴"]
        case .guitar:
            var missing: [String] = []
            if !capabilities.supports(.guitarPluck) { missing.append("吉他拨弦") }
            if !capabilities.supports(.guitarFret) { missing.append("吉他品位") }
            if !capabilities.supports(.chords) { missing.append("吉他和弦") }
            return missing
        case .drums:
            return capabilities.supports(.drums) ? [] : ["九鼓"]
        }
    }
}

final class PracticePerformanceController: ObservableObject {
    @Published private(set) var lastFailure = ""
    @Published private(set) var activePage: PracticeGameKind?

    private weak var router: FreePlayEventRouter?
    private weak var bluetooth: InstrumentBluetooth?
    private var localPrepare: (() -> Void)?
    private var localStop: (() -> Void)?
    private var guitarState: (() -> PracticeGuitarState)?
    private var savedDamping: Bool?
    private var savedPedalDown: Bool?
    private var pianoTokens: [Int: UInt32] = [:]
    private var nextToken: UInt32 = 7_000_000
    private var pageToken: UUID?

    func attach(router: FreePlayEventRouter, bluetooth: InstrumentBluetooth) {
        self.router = router
        self.bluetooth = bluetooth
    }

    @discardableResult
    func beginPage(
        _ kind: PracticeGameKind,
        prepareLocal: @escaping () -> Void,
        stopLocal: @escaping () -> Void,
        guitarState: (() -> PracticeGuitarState)? = nil
    ) -> UUID {
        if activePage != nil {
            endPage(reason: .leavePage)
        }
        let token = UUID()
        pageToken = token
        activePage = kind
        localPrepare = prepareLocal
        localStop = stopLocal
        self.guitarState = guitarState
        lastFailure = ""
        pianoTokens.removeAll(keepingCapacity: true)

        guard let router else {
            localPrepare?()
            lastFailure = "BLE 未连接；使用 iPad 本地声音"
            return token
        }

        savedDamping = router.damping
        savedPedalDown = router.pedalDown
        router.attach(audio: nil, sink: bluetooth)
        if router.isHardwareMode && !canUseHardware(kind) {
            _ = router.setMode(.localDemo)
            lastFailure = "\(kind.title)：\(hardwareUnavailableReason(kind))；已使用 iPad 本地声音"
            localPrepare?()
            return token
        }

        prepareRouterState(kind)
        if router.isHardwareMode {
            localStop?()
            router.resumeHardwareSession()
        } else {
            localPrepare?()
        }
        return token
    }

    func endPage(token: UUID, reason: PerformanceReleaseReason = .leavePage) {
        guard token == pageToken else { return }
        endPage(reason: reason)
    }

    func endPage(reason: PerformanceReleaseReason = .leavePage) {
        guard activePage != nil else { return }
        let restoreDamping = savedDamping
        let restorePedal = savedPedalDown
        releaseCurrentPage(reason: reason)
        if let router {
            if let restoreDamping {
                _ = router.setDamping(restoreDamping)
            }
            if let restorePedal, restoreDamping ?? true {
                _ = router.setPedal(restorePedal)
            }
        }
        savedDamping = nil
        savedPedalDown = nil
        activePage = nil
        pageToken = nil
        localPrepare = nil
        localStop = nil
        guitarState = nil
    }

    func releaseCurrentPage(token: UUID, reason: PerformanceReleaseReason = .leavePage) {
        guard token == pageToken else { return }
        releaseCurrentPage(reason: reason)
    }

    func releaseCurrentPage(reason: PerformanceReleaseReason = .leavePage) {
        pianoTokens.removeAll(keepingCapacity: true)
        if let router, router.isHardwareMode {
            router.allNotesOff(reason: reason)
        }
        localStop?()
    }

    func canUseHardware(_ kind: PracticeGameKind) -> Bool {
        guard let router, router.isHardwareAvailable, let capabilities = router.capabilities else {
            return false
        }
        return kind.isPlayable(with: capabilities)
    }

    func hardwareUnavailableReason(_ kind: PracticeGameKind) -> String {
        guard let router else { return "BLE 未连接" }
        guard router.isHardwareAvailable else { return "BLE 未连接或演奏能力未确认" }
        guard let capabilities = router.capabilities else { return "演奏能力未确认" }
        let missing = kind.missingControls(with: capabilities)
        guard !missing.isEmpty else { return "FPGA 能力可用" }
        let version = capabilities.isV1 ? "v1" : "v2"
        return "FPGA \(version) 缺少 \(missing.joined(separator: "、"))"
    }

    @discardableResult
    func setMode(_ newMode: PerformanceMode, for kind: PracticeGameKind) -> Bool {
        guard let router else {
            lastFailure = "BLE 未连接；只能使用 iPad 本地声音"
            localPrepare?()
            return false
        }
        if newMode == .bleInstrument {
            guard canUseHardware(kind) else {
                lastFailure = "\(kind.title)：\(hardwareUnavailableReason(kind))"
                if !router.isHardwareMode {
                    localPrepare?()
                }
                return false
            }
            router.attach(audio: nil, sink: bluetooth)
            if savedDamping == nil {
                savedDamping = router.damping
                savedPedalDown = router.pedalDown
            }
            prepareRouterState(kind)
            guard router.setMode(.bleInstrument) else {
                lastFailure = router.lastFailure.isEmpty ? "无法切换 FPGA音箱" : router.lastFailure
                localPrepare?()
                return false
            }
            localStop?()
            router.resumeHardwareSession()
            lastFailure = ""
            return true
        }

        pianoTokens.removeAll(keepingCapacity: true)
        _ = router.setMode(.localDemo)
        localPrepare?()
        lastFailure = ""
        return true
    }

    func pianoDown(
        lane: Int,
        keyID: Int,
        midiNote: Int,
        velocity: Int,
        local: () -> Void
    ) {
        if let router, router.isHardwareMode {
            guard canUseHardware(.piano), router.supports(.piano) else {
                lastFailure = "FPGA 未声明钢琴能力"
                return
            }
            guard pianoTokens[lane] == nil else { return }
            let token = nextToken
            nextToken &+= 1
            pianoTokens[lane] = token
            router.pianoDown(
                token: token,
                keyID: keyID,
                midiNote: midiNote,
                velocity: velocity
            )
        } else {
            local()
        }
    }

    func pianoUp(lane: Int, reason: PerformanceReleaseReason = .release) {
        guard let token = pianoTokens.removeValue(forKey: lane) else { return }
        guard let router, router.isHardwareMode else { return }
        _ = router.pianoUp(token: token, reason: reason)
    }

    func drumHit(
        instrument: DrumKitInstrument,
        velocity: Int,
        local: () -> Void
    ) {
        if let router, router.isHardwareMode {
            guard canUseHardware(.drums) else {
                lastFailure = "FPGA 未声明九鼓能力"
                return
            }
            let token = nextToken
            nextToken &+= 1
            router.drumHit(token: token, pad: instrument.rawValue, velocity: velocity)
        } else {
            local()
        }
    }

    func guitarSelectFret(_ fret: Int) {
        guard activePage == .guitar, let router else { return }
        _ = router.setFret(fret)
    }

    func guitarSelectChord(_ chordID: Int) {
        guard activePage == .guitar, let router, router.isHardwareMode,
              canUseHardware(.guitar) else { return }
        _ = router.selectChord(chordID)
    }

    func guitarPluck(
        stringIndex: Int,
        selectedFret: Int,
        selectedChordID: Int?,
        velocity: Int,
        local: () -> Void
    ) {
        guard activePage == .guitar else {
            local()
            return
        }
        guard let router, router.isHardwareMode else {
            local()
            return
        }
        guard canUseHardware(.guitar) else {
            lastFailure = "FPGA 未声明吉他品位/和弦能力"
            return
        }

        if let chordID = selectedChordID {
            router.chordTrigger(chordID: chordID, velocity: velocity)
            return
        }

        guard FPGAKeyMap.guitarStrings.indices.contains(stringIndex) else { return }
        if router.fret != selectedFret {
            _ = router.setFret(selectedFret)
        }
        let string = FPGAKeyMap.guitarStrings[stringIndex]
        let token = nextToken
        nextToken &+= 1
        router.stringDown(
            token: token,
            stringIndex: stringIndex,
            fret: selectedFret,
            midiNote: string.openMIDINote + selectedFret,
            velocity: velocity
        )
    }

    func handleConnectionLost() {
        pianoTokens.removeAll(keepingCapacity: true)
        guard activePage != nil else { return }
        lastFailure = "BLE 断线：音游使用 iPad 本地声音"
        localPrepare?()
    }

    func handleCapabilityLost() {
        guard activePage != nil, let router, router.isHardwareMode else { return }
        pianoTokens.removeAll(keepingCapacity: true)
        _ = router.setMode(.localDemo)
        lastFailure = "BLE 能力失效：音游使用 iPad 本地声音"
        localPrepare?()
    }

    private func prepareRouterState(_ kind: PracticeGameKind) {
        guard let router else { return }
        if !router.isHardwareMode || router.supports(.pianoOctave) {
            _ = router.setOctave(1)
        }
        if !router.isHardwareMode || router.supports(.dampingPedal) {
            _ = router.setDamping(true)
            _ = router.setPedal(false)
        }
        if !router.isHardwareMode || router.supports(.guitarPalm) {
            _ = router.setPalm(false)
        }
        if !router.isHardwareMode || router.supports(.bendVibrato) {
            _ = router.setBend(.center)
            _ = router.setVibrato(false)
        }
        if !router.isHardwareMode || router.supports(.glideSlide) {
            _ = router.setGlide(false)
        }

        if kind == .guitar, let state = guitarState?() {
            if !router.isHardwareMode || router.supports(.guitarFret) {
                _ = router.setFret(state.fret)
            }
        }
    }
}

struct PracticeSourceControl: View {
    let kind: PracticeGameKind
    @EnvironmentObject private var performance: PracticePerformanceController
    @EnvironmentObject private var router: FreePlayEventRouter
    @EnvironmentObject private var bluetooth: InstrumentBluetooth

    var body: some View {
        HStack(spacing: 5) {
            Text("音源")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            sourceButton(title: "iPad本地", mode: .localDemo)
            sourceButton(title: "FPGA音箱", mode: .bleInstrument)
                .disabled(!performance.canUseHardware(kind))
                .opacity(performance.canUseHardware(kind) ? 1 : 0.42)
            Text(router.mode.title)
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(router.isHardwareMode ? PixelPalette.good : PixelPalette.muted)
            if !performance.canUseHardware(kind) {
                Text(performance.hardwareUnavailableReason(kind))
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if !performance.lastFailure.isEmpty {
                Text(performance.lastFailure)
                    .font(.system(size: 8, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.miss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(bluetooth.isReady ? "BLE 已连接" : "BLE 未连接")
                .font(.system(size: 7, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(PixelPanelShape(cut: 4).fill(PixelPalette.secondary))
        .overlay(PixelPanelShape(cut: 4).stroke(PixelPalette.line, lineWidth: 0.8))
    }

    private func sourceButton(title: String, mode: PerformanceMode) -> some View {
        Button {
            _ = performance.setMode(mode, for: kind)
        } label: {
            Text(title)
                .font(.system(size: 8, weight: .heavy, design: .serif))
                .foregroundStyle(router.mode == mode ? PixelPalette.card : PixelPalette.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(router.mode == mode ? PixelPalette.accentDark : PixelPalette.card)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}
