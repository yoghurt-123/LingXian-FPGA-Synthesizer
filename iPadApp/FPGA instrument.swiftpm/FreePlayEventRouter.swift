import Foundation
import Combine

protocol PerformanceEventSink: AnyObject {
    var isPerformanceSinkAvailable: Bool { get }
    var performanceSinkDescription: String { get }
    var performanceCapabilities: PerformanceCapabilities? { get }
    func submitPerformanceGroup(_ group: PerformancePacketGroup) -> Bool
}

final class FreePlayEventRouter: ObservableObject {
    @Published private(set) var mode: PerformanceMode = .localDemo
    @Published private(set) var lastEventText: String = "等待演奏"
    @Published private(set) var lastFailure: String = ""

    @Published private(set) var octave: Int = 1
    @Published private(set) var fret: Int = 0
    @Published private(set) var palmMuted: Bool = false
    @Published private(set) var damping: Bool = true
    @Published private(set) var pedalDown: Bool = false
    @Published private(set) var bend: PerformanceBend = .center
    @Published private(set) var vibrato: Bool = false
    @Published private(set) var glide: Bool = false
    @Published private(set) var slideStep: Int = 4
    @Published private(set) var overdriveTarget: Bool? = nil
    @Published private(set) var reverbTarget: Bool? = nil
    @Published private(set) var lastChordID: Int? = nil
    @Published private(set) var lastChordText: String = ""

    private weak var audio: FreePlayAudio?
    private weak var sink: PerformanceEventSink?
    private var ledger = PerformanceSessionLedger()
    private var nextTransientToken: UInt32 = 1_000_000

    var heldCount: Int { ledger.count }
    var isHardwareMode: Bool { mode == .bleInstrument }
    var isHardwareAvailable: Bool { sink?.isPerformanceSinkAvailable ?? false }
    var sinkDescription: String { sink?.performanceSinkDescription ?? "BLE 未连接" }
    var capabilities: PerformanceCapabilities? { sink?.performanceCapabilities }
    var isV2Hardware: Bool { isHardwareMode && capabilities?.supportsExtendedEvents == true }
    var slideMilliseconds: Int { PerformanceSlideTime.milliseconds(for: slideStep) }
    var protocolLabel: String {
        guard let capabilities else { return "BLE 未连接" }
        return capabilities.isV1 ? "协议 v1 基础" : "协议 v2 扩展"
    }

    func attach(audio: FreePlayAudio?, sink: PerformanceEventSink?) {
        self.audio = audio
        self.sink = sink
    }

    func supports(_ control: PerformanceControl) -> Bool {
        guard isHardwareMode else { return true }
        return capabilities?.supports(control) ?? false
    }

    func hardwareSupports(_ control: PerformanceControl) -> Bool {
        capabilities?.supports(control) ?? false
    }

    @discardableResult
    func setMode(_ newMode: PerformanceMode) -> Bool {
        guard newMode != mode else { return true }
        if newMode == .bleInstrument {
            guard isHardwareAvailable else {
                lastFailure = "蓝牙演奏协议未就位，不能切换 FPGA 音箱"
                return false
            }
            audio?.stopAll()
            _ = ledger.releaseAll(reason: .modeChange)
            resetTransientExpression()
            mode = .bleInstrument
            lastEventText = "FPGA音箱：准备恢复演奏状态"
            _ = restoreHardwareState()
            return true
        }

        if mode == .bleInstrument {
            _ = sendCleanup(reason: .modeChange)
        }
        mode = .localDemo
        resetTransientExpression()
        audio?.prepare()
        lastEventText = "iPad本地声音"
        return true
    }

    func makeTransientToken() -> UInt32 {
        let token = nextTransientToken
        nextTransientToken &+= 1
        return token
    }

    func pianoDown(token: UInt32, keyID: Int, midiNote: Int, velocity: Int) {
        if mode == .localDemo {
            audio?.playPiano(midiNote: midiNote, velocity: velocity)
            let displaced = ledger.hold(token: token, instrument: .piano, key: keyID)
            for item in displaced { _ = sendNoteOff(item, reason: .slideOut) }
            lastEventText = "本地钢琴：\(keyID)"
            lastFailure = ""
            return
        }
        guard let wire = encoder(), supports(.piano),
              let group = wire.pianoNoteOn(key: keyID, velocity: velocity, octave: octave) else {
            lastFailure = "FPGA 未声明钢琴基础能力"
            return
        }
        guard submit(group) else { return }
        let displaced = ledger.hold(token: token, instrument: .piano, key: keyID)
        for item in displaced { _ = sendNoteOff(item, reason: .slideOut) }
        lastEventText = "FPGA钢琴：\(keyID) · 力度\(velocity)"
        lastFailure = ""
    }

    @discardableResult
    func pianoUp(token: UInt32, reason: PerformanceReleaseReason) -> Bool {
        guard let held = ledger.holds[token] else { return true }
        if mode == .bleInstrument {
            guard sendNoteOff(
                PerformanceReleasedNote(
                    token: held.token,
                    instrument: held.instrument,
                    key: held.key,
                    reason: reason
                ),
                reason: reason
            ) else {
                lastFailure = "钢琴释放未发送；保持待释放状态"
                return false
            }
        }
        _ = ledger.release(token: token, reason: reason)
        lastEventText = "\(mode.title) · 释放 \(reason.title)"
        lastFailure = ""
        return true
    }

    func pianoMoved(token: UInt32, fromKey: Int, toKey: Int?, midiNote: Int, velocity: Int) {
        guard pianoUp(token: token, reason: .slideOut) else { return }
        guard let toKey else { return }
        pianoDown(token: token, keyID: toKey, midiNote: midiNote, velocity: velocity)
    }

    func stringDown(token: UInt32, stringIndex: Int, fret: Int, midiNote: Int, velocity: Int) {
        if mode == .localDemo {
            audio?.playString(stringIndex: stringIndex, fret: fret, velocity: velocity)
            lastEventText = "本地吉他：\(stringIndex + 1)弦 \(fret)品"
            lastFailure = ""
            return
        }
        guard let wire = encoder(), supports(.guitarPluck),
              let group = wire.guitarPluck(
                string: stringIndex,
                velocity: velocity,
                fret: self.fret,
                palmMuted: palmMuted
              ) else {
            lastFailure = "FPGA 未声明吉他拨弦能力"
            return
        }
        guard submit(group) else { return }
        lastEventText = "FPGA吉他：\(stringIndex + 1)弦 · \(self.fret)品 · 力度\(velocity)"
        lastFailure = ""
    }

    func stringUp(token: UInt32, reason: PerformanceReleaseReason) {
        if mode == .localDemo {
            lastEventText = "本地：吉他松手"
        } else {
            lastEventText = "FPGA 吉他一次性拨弦；松手不发 note-off"
        }
    }

    func stringMoved(token: UInt32, fromString: Int, toString: Int?) {
        if mode == .localDemo {
            lastEventText = "本地：吉他滑出"
        } else {
            lastEventText = "FPGA 吉他一次性拨弦；滑出不重触发"
        }
    }

    func drumHit(token: UInt32, pad: Int, velocity: Int) {
        if mode == .localDemo {
            if let instrument = DrumKitInstrument(rawValue: pad) {
                audio?.playDrum(instrument, velocity: velocity)
            }
            lastEventText = "本地鼓：\(pad)"
            lastFailure = ""
            return
        }
        let protocolKey = DrumKitInstrument(rawValue: pad)?.bleProtocolKey ?? pad
        guard let wire = encoder(), supports(.drums),
              let group = wire.drum(key: protocolKey, velocity: velocity) else {
            lastFailure = "FPGA 未声明九鼓能力"
            return
        }
        if submit(group) {
            lastEventText = "FPGA鼓：\(protocolKey)"
            lastFailure = ""
        }
    }

    func selectChord(_ chordID: Int) {
        guard mode == .bleInstrument else { return }
        guard supports(.chords), let group = encoder()?.chordSelect(chordID) else {
            lastFailure = "FPGA 未声明和弦能力"
            return
        }
        guard submit(group) else { return }
        lastEventText = "FPGA和弦选择：\(chordID)"
        lastFailure = ""
    }

    func chordTrigger(chordID: Int, velocity: Int) {
        if mode == .localDemo {
            if let chord = FPGAKeyMap.guitarChords.first(where: { $0.id == chordID }) {
                audio?.playChord(chord, velocity: velocity)
            }
            lastEventText = "本地和弦：\(chordID)"
            lastFailure = ""
            return
        }
        guard let wire = encoder(), supports(.chords),
              let group = wire.chord(chordID: chordID, velocity: velocity) else {
            lastFailure = "FPGA 未声明和弦能力"
            return
        }
        guard submit(group) else { return }
        lastChordID = chordID
        let name = FPGAKeyMap.guitarChords.first { $0.id == chordID }?.name ?? "\(chordID)"
        lastChordText = "\(name) 已触发：短促一次性，松手不会立即制音"
        lastEventText = "FPGA和弦：\(name)"
        lastFailure = ""
    }

    func setOctave(_ value: Int) {
        let safe = min(max(value, 0), 2)
        if mode == .localDemo {
            octave = safe
            lastEventText = "本地八度：\(octaveTitle(safe))"
            return
        }
        guard supports(.pianoOctave), let group = encoder()?.octave(safe) else {
            lastFailure = "FPGA 未声明钢琴八度能力"
            return
        }
        guard submit(group) else { return }
        octave = safe
        lastEventText = "FPGA八度目标：\(octaveTitle(safe))"
        lastFailure = ""
    }

    func setFret(_ value: Int) {
        let safe = min(max(value, 0), 12)
        if mode == .localDemo {
            fret = safe
            lastEventText = "本地品位：\(safe)"
            return
        }
        guard supports(.guitarFret), let group = encoder()?.fret(safe) else {
            lastFailure = "FPGA 未声明吉他品位能力"
            return
        }
        guard submit(group) else { return }
        fret = safe
        lastEventText = "FPGA品位目标：\(safe)"
        lastFailure = ""
    }

    func setPalm(_ muted: Bool) {
        if mode == .localDemo {
            palmMuted = muted
            return
        }
        guard supports(.guitarPalm), let group = encoder()?.palm(muted) else {
            lastFailure = "FPGA 未声明掌根闷音能力"
            return
        }
        guard submit(group) else { return }
        palmMuted = muted
        lastEventText = "掌根闷音目标：\(muted ? "开" : "关")"
        lastFailure = ""
    }

    func setDamping(_ enabled: Bool) {
        if mode == .localDemo {
            damping = enabled
            return
        }
        guard supports(.dampingPedal), let group = encoder()?.damping(enabled) else {
            lastFailure = "FPGA 未声明阻尼/踏板能力"
            return
        }
        guard submit(group) else { return }
        if !enabled, pedalDown {
            if let pedalGroup = encoder()?.pedal(false) {
                _ = submit(pedalGroup)
            }
            pedalDown = false
        }
        damping = enabled
        lastEventText = "钢琴阻尼目标：\(enabled ? "开（松键释放）" : "关（自然衰减）")"
        lastFailure = ""
    }

    @discardableResult
    func setPedal(_ down: Bool) -> Bool {
        if mode == .localDemo {
            pedalDown = down
            return true
        }
        guard damping else {
            lastFailure = "阻尼关闭时踏板不生效"
            return false
        }
        guard supports(.dampingPedal), let group = encoder()?.pedal(down) else {
            lastFailure = "FPGA 未声明阻尼/踏板能力"
            return false
        }
        guard submit(group) else { return false }
        pedalDown = down
        lastEventText = down ? "钢琴踏板目标：按下" : "钢琴踏板目标：释放"
        lastFailure = ""
        return true
    }

    func releasePendingPedal() {
        guard mode == .bleInstrument else { return }
        guard supports(.dampingPedal), let group = encoder()?.pedalRelease() else {
            lastFailure = "FPGA 未声明踏板释放能力"
            return
        }
        guard submit(group) else { return }
        pedalDown = false
        lastEventText = "已发送释放待处理踏板音"
        lastFailure = ""
    }

    func setBend(_ state: PerformanceBend) {
        if mode == .localDemo {
            bend = state
            return
        }
        guard supports(.bendVibrato), let group = encoder()?.bend(state) else {
            lastFailure = "FPGA 未声明弯音能力"
            return
        }
        guard submit(group) else { return }
        bend = state
        lastEventText = "弯音目标：\(state.title)"
        lastFailure = ""
    }

    func setVibrato(_ enabled: Bool) {
        if mode == .localDemo {
            vibrato = enabled
            return
        }
        guard supports(.bendVibrato), let group = encoder()?.vibrato(enabled) else {
            lastFailure = "FPGA 未声明颤音能力"
            return
        }
        guard submit(group) else { return }
        vibrato = enabled
        lastEventText = "颤音开关目标：\(enabled ? "开" : "关")"
        lastFailure = ""
    }

    func setGlide(_ enabled: Bool) {
        if mode == .localDemo {
            glide = enabled
            return
        }
        guard supports(.glideSlide), let group = encoder()?.glide(enabled) else {
            lastFailure = "FPGA 未声明滑音能力"
            return
        }
        guard submit(group) else { return }
        glide = enabled
        lastEventText = "滑音开关目标：\(enabled ? "开" : "关")"
        lastFailure = ""
    }

    func setSlideStep(_ step: Int) {
        let safe = min(max(step, PerformanceSlideTime.range.lowerBound), PerformanceSlideTime.range.upperBound)
        if mode == .localDemo {
            slideStep = safe
            return
        }
        guard supports(.glideSlide), let group = encoder()?.slideStep(safe) else {
            lastFailure = "FPGA 未声明滑音时间能力"
            return
        }
        guard submit(group) else { return }
        slideStep = safe
        lastEventText = "滑音时间目标：\(PerformanceSlideTime.label(for: safe))"
        lastFailure = ""
    }

    func setOverdrive(_ enabled: Bool) {
        guard mode == .bleInstrument else { return }
        guard supports(.overdrive), let group = encoder()?.overdrive(enabled) else {
            lastFailure = "FPGA 未声明过载能力"
            return
        }
        guard submit(group) else { return }
        overdriveTarget = enabled
        lastEventText = "过载 App目标：\(enabled ? "开" : "关") · 共享效果链未回报"
        lastFailure = ""
    }

    func setReverb(_ enabled: Bool) {
        guard mode == .bleInstrument else { return }
        guard supports(.reverb), let group = encoder()?.reverb(enabled) else {
            lastFailure = "FPGA 未声明混响能力"
            return
        }
        guard submit(group) else { return }
        reverbTarget = enabled
        lastEventText = "混响 App目标：\(enabled ? "开" : "关") · 共享效果链未回报"
        lastFailure = ""
    }

    func resumeHardwareSession() {
        guard mode == .bleInstrument else { return }
        guard isHardwareAvailable else {
            lastFailure = "BLE 演奏协议不可用"
            return
        }
        audio?.stopAll()
        resetTransientExpression()
        if isV2Hardware {
            _ = restoreHardwareState()
        } else {
            lastEventText = "FPGA协议 v1 基础演奏"
        }
    }

    func allNotesOff(reason: PerformanceReleaseReason) {
        if mode == .bleInstrument {
            if reason == .panic {
                if let group = encoder()?.allStop() {
                    _ = submit(group)
                } else {
                    _ = sendCleanup(reason: reason)
                }
                _ = ledger.clearAfterDisconnect()
                resetTransientExpression()
                lastEventText = "FPGA 全局停止（独立于 BLE 释放）"
            } else {
                _ = sendCleanup(reason: reason)
                lastEventText = "FPGA 演奏清理：\(reason.title)"
            }
        } else {
            _ = ledger.releaseAll(reason: reason)
            lastEventText = "本地释放：\(reason.title)"
        }
        lastChordID = nil
        lastChordText = ""
        audio?.stopAll()
    }

    func releaseAll(reason: PerformanceReleaseReason) {
        allNotesOff(reason: reason)
    }

    func handleDisconnect() {
        _ = ledger.clearAfterDisconnect()
        audio?.stopAll()
        if mode == .bleInstrument {
            mode = .localDemo
            lastEventText = "BLE 断线，返回 iPad本地声音"
            audio?.prepare()
        }
        resetTransientExpression()
        overdriveTarget = nil
        reverbTarget = nil
        lastChordID = nil
        lastChordText = ""
        lastFailure = "BLE 已断开，停止演奏；由 ESP/FPGA 兜底"
    }

    func handleCapabilityLost() {
        _ = ledger.clearAfterDisconnect()
        audio?.stopAll()
        if mode == .bleInstrument {
            mode = .localDemo
            lastEventText = "能力失效，返回 iPad本地声音"
            audio?.prepare()
        }
        resetTransientExpression()
        overdriveTarget = nil
        reverbTarget = nil
        lastChordID = nil
        lastChordText = ""
        lastFailure = "BLE 能力失效；已尝试释放，硬件模式关闭"
    }

    private func restoreHardwareState() -> Bool {
        guard isV2Hardware, let wire = encoder() else {
            lastEventText = "FPGA协议 v1 基础演奏"
            return true
        }
        guard let group = wire.restoreGroup(
            octave: octave,
            fret: fret,
            palmMuted: palmMuted,
            damping: damping,
            pedalDown: false,
            bendState: .center,
            vibrato: false,
            glide: false,
            slideStep: slideStep
        ) else {
            lastEventText = "FPGA协议 v2：无可恢复参数"
            return true
        }
        guard submit(group) else { return false }
        lastEventText = "已按 App 目标恢复八度/品位/掌根/阻尼/踏板"
        return true
    }

    @discardableResult
    private func sendCleanup(reason: PerformanceReleaseReason) -> Bool {
        let released = ledger.releaseAll(reason: reason)
        let wire = encoder()
        if let group = wire?.cleanupExpressionAndRelease() {
            let accepted = submit(group)
            resetTransientExpression()
            let releaseSupported = wire?.supports(.releaseAll) == true
            if !accepted || !releaseSupported {
                for item in released where item.instrument == .piano {
                    _ = sendNoteOff(item, reason: reason)
                }
            }
            return accepted
        }
        var accepted = true
        for item in released where item.instrument == .piano {
            if !sendNoteOff(item, reason: reason) { accepted = false }
        }
        resetTransientExpression()
        return accepted
    }

    @discardableResult
    private func sendNoteOff(_ item: PerformanceReleasedNote, reason: PerformanceReleaseReason) -> Bool {
        guard mode == .bleInstrument else { return true }
        guard let group = encoder()?.pianoNoteOff(key: item.key) else {
            lastFailure = "FPGA 未声明钢琴释放能力"
            return false
        }
        return submit(group)
    }

    private func resetTransientExpression() {
        bend = .center
        vibrato = false
        glide = false
        pedalDown = false
    }

    private func submit(_ group: PerformancePacketGroup) -> Bool {
        guard let sink else {
            lastFailure = "BLE 未连接"
            return false
        }
        guard sink.isPerformanceSinkAvailable else {
            lastFailure = sink.performanceSinkDescription
            return false
        }
        let accepted = sink.submitPerformanceGroup(group)
        if accepted {
            lastFailure = ""
        } else {
            lastFailure = sink.performanceSinkDescription
        }
        return accepted
    }

    private func encoder() -> PerformanceWireEncoder? {
        guard let capabilities = sink?.performanceCapabilities else { return nil }
        return PerformanceWireEncoder(capabilities: capabilities)
    }

    private func octaveTitle(_ value: Int) -> String {
        switch value {
        case 0: return "低"
        case 2: return "高"
        default: return "原"
        }
    }
}

