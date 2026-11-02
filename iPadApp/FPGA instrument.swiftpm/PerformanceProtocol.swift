import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable, Equatable {
    case localDemo
    case bleInstrument

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localDemo: return "iPad本地声音"
        case .bleInstrument: return "FPGA音箱"
        }
    }
}

enum PerformanceInstrument: UInt8, CaseIterable, Identifiable, Equatable {
    case piano = 1
    case guitar = 2
    case drums = 3

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .piano: return "钢琴"
        case .guitar: return "电吉他"
        case .drums: return "九鼓"
        }
    }
}

enum PerformanceEventKind: UInt8, Equatable {
    case noteOn = 1
    case noteOff = 2
    case chordTrigger = 3
    case drumTrigger = 4
    case parameter = 5
    case allNotesOff = 6

    var title: String {
        switch self {
        case .noteOn: return "按下"
        case .noteOff: return "释放"
        case .chordTrigger: return "和弦触发"
        case .drumTrigger: return "鼓触发"
        case .parameter: return "参数"
        case .allNotesOff: return "全部释放"
        }
    }
}

enum PerformanceReleaseReason: UInt8, Equatable {
    case release = 1
    case slideOut = 2
    case cancel = 3
    case modeChange = 4
    case leavePage = 5
    case background = 6
    case disconnect = 7
    case panic = 8

    var title: String {
        switch self {
        case .release: return "松手"
        case .slideOut: return "滑出"
        case .cancel: return "触摸取消"
        case .modeChange: return "切换模式"
        case .leavePage: return "离开页面"
        case .background: return "进入后台"
        case .disconnect: return "断线"
        case .panic: return "全部停止"
        }
    }
}

enum PerformanceParameter: UInt8, CaseIterable, Identifiable, Equatable {
    case velocity = 1
    case octave = 2
    case fret = 3
    case chord = 4
    case masterVolume = 5
    case glideEnabled = 6
    case slideMilliseconds = 7
    case bend = 8
    case vibrato = 9
    case palmMute = 10
    case overdrive = 11
    case reverb = 12
    case pedalMode = 13
    case pedalHold = 14

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .velocity: return "力度"
        case .octave: return "钢琴八度"
        case .fret: return "吉他品位"
        case .chord: return "吉他和弦"
        case .masterVolume: return "总音量"
        case .glideEnabled: return "滑音开关"
        case .slideMilliseconds: return "滑音时间"
        case .bend: return "弯音"
        case .vibrato: return "颤音"
        case .palmMute: return "掌根闷音"
        case .overdrive: return "过载"
        case .reverb: return "混响"
        case .pedalMode: return "钢琴踏板模式"
        case .pedalHold: return "延音踏板"
        }
    }

    enum ValueKind: String {
        case momentary
        case targetState
        case continuous
    }

    var valueKind: ValueKind {
        switch self {
        case .velocity, .octave, .fret, .chord:
            return .targetState
        case .masterVolume, .slideMilliseconds, .bend, .vibrato, .pedalHold:
            return .continuous
        case .glideEnabled, .palmMute, .overdrive, .reverb, .pedalMode:
            return .targetState
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .velocity: return 0...15
        case .octave: return 0...2
        case .fret: return 0...12
        case .chord: return 0...3
        case .masterVolume: return 0...1
        case .slideMilliseconds: return 20...300
        case .bend: return -2...2
        case .vibrato: return 0...1
        case .glideEnabled, .palmMute, .overdrive, .reverb, .pedalMode, .pedalHold:
            return 0...1
        }
    }
}

struct PerformanceEvent: Equatable {
    let sequence: UInt32
    let kind: PerformanceEventKind
    let instrument: PerformanceInstrument?
    let sourceToken: UInt32?
    let key: Int
    let velocity: Int
    let fret: Int?
    let value: Double?
    let reason: PerformanceReleaseReason?
    let timestamp: TimeInterval

    static func noteOn(
        sequence: UInt32,
        instrument: PerformanceInstrument,
        token: UInt32,
        key: Int,
        velocity: Int,
        fret: Int? = nil,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .noteOn,
            instrument: instrument,
            sourceToken: token,
            key: key,
            velocity: velocity,
            fret: fret,
            value: nil,
            reason: nil,
            timestamp: timestamp
        )
    }

    static func noteOff(
        sequence: UInt32,
        instrument: PerformanceInstrument,
        token: UInt32,
        key: Int,
        reason: PerformanceReleaseReason,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .noteOff,
            instrument: instrument,
            sourceToken: token,
            key: key,
            velocity: 0,
            fret: nil,
            value: nil,
            reason: reason,
            timestamp: timestamp
        )
    }

    static func drum(
        sequence: UInt32,
        token: UInt32,
        pad: Int,
        velocity: Int,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .drumTrigger,
            instrument: .drums,
            sourceToken: token,
            key: pad,
            velocity: velocity,
            fret: nil,
            value: nil,
            reason: nil,
            timestamp: timestamp
        )
    }

    static func chord(
        sequence: UInt32,
        token: UInt32,
        chordID: Int,
        velocity: Int,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .chordTrigger,
            instrument: .guitar,
            sourceToken: token,
            key: chordID,
            velocity: velocity,
            fret: nil,
            value: Double(chordID),
            reason: nil,
            timestamp: timestamp
        )
    }

    static func parameter(
        sequence: UInt32,
        instrument: PerformanceInstrument?,
        parameter: PerformanceParameter,
        value: Double,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .parameter,
            instrument: instrument,
            sourceToken: nil,
            key: Int(parameter.rawValue),
            velocity: 0,
            fret: nil,
            value: value,
            reason: nil,
            timestamp: timestamp
        )
    }

    static func allNotesOff(
        sequence: UInt32,
        reason: PerformanceReleaseReason,
        timestamp: TimeInterval
    ) -> PerformanceEvent {
        PerformanceEvent(
            sequence: sequence,
            kind: .allNotesOff,
            instrument: nil,
            sourceToken: nil,
            key: 0,
            velocity: 0,
            fret: nil,
            value: nil,
            reason: reason,
            timestamp: timestamp
        )
    }
}

struct PerformanceHeldNote: Equatable {
    let token: UInt32
    let instrument: PerformanceInstrument
    let key: Int
    let chordID: Int?
}

struct PerformanceReleasedNote: Equatable {
    let token: UInt32
    let instrument: PerformanceInstrument
    let key: Int
    let reason: PerformanceReleaseReason
}

struct PerformanceSessionLedger {
    private(set) var holds: [UInt32: PerformanceHeldNote] = [:]

    var count: Int { holds.count }

    mutating func hold(
        token: UInt32,
        instrument: PerformanceInstrument,
        key: Int,
        chordID: Int? = nil
    ) -> [PerformanceReleasedNote] {
        var releases: [PerformanceReleasedNote] = []
        if let existing = holds[token] {
            releases.append(
                PerformanceReleasedNote(
                    token: existing.token,
                    instrument: existing.instrument,
                    key: existing.key,
                    reason: .slideOut
                )
            )
        }
        holds[token] = PerformanceHeldNote(
            token: token,
            instrument: instrument,
            key: key,
            chordID: chordID
        )
        return releases
    }

    mutating func release(token: UInt32, reason: PerformanceReleaseReason) -> PerformanceReleasedNote? {
        guard let held = holds.removeValue(forKey: token) else { return nil }
        return PerformanceReleasedNote(
            token: held.token,
            instrument: held.instrument,
            key: held.key,
            reason: reason
        )
    }

    mutating func releaseAll(reason: PerformanceReleaseReason) -> [PerformanceReleasedNote] {
        let held = holds.values.sorted { $0.token < $1.token }
        holds.removeAll(keepingCapacity: true)
        return held.map {
            PerformanceReleasedNote(
                token: $0.token,
                instrument: $0.instrument,
                key: $0.key,
                reason: reason
            )
        }
    }

    mutating func clearAfterDisconnect() -> [PerformanceReleasedNote] {
        let values = holds.values.sorted { $0.token < $1.token }
        holds.removeAll(keepingCapacity: true)
        return values.map {
            PerformanceReleasedNote(
                token: $0.token,
                instrument: $0.instrument,
                key: $0.key,
                reason: .disconnect
            )
        }
    }
}

enum PerformanceControlInventory {
    static let pianoKeyIDs: [Int] = FPGAKeyMap.pianoKeys.map(\.id)
    static let guitarStringIndexes: [Int] = Array(0..<FPGAKeyMap.guitarStrings.count)
    static let guitarFrets: ClosedRange<Int> = 0...12
    static let chordIDs: [Int] = FPGAKeyMap.guitarChords.map(\.id)
    static let drumIDs: [Int] = FPGAKeyMap.drumPads.map(\.id)
    static let velocityCodes: ClosedRange<Int> = 0...15
    static let octaves: ClosedRange<Int> = 0...2

    static func validationError(for event: PerformanceEvent) -> String? {
        switch event.kind {
        case .noteOn, .noteOff:
            if event.instrument == .piano {
                return pianoKeyIDs.contains(event.key) ? nil : "钢琴键 ID 越界"
            }
            if event.instrument == .guitar {
                guard guitarStringIndexes.contains(event.key) else { return "吉他弦索引越界" }
                if let fret = event.fret {
                    guard guitarFrets.contains(fret) else { return "吉他品位越界" }
                }
                return nil
            }
            return "音符事件缺少有效乐器"
        case .chordTrigger:
            return chordIDs.contains(event.key) ? nil : "和弦 ID 越界"
        case .drumTrigger:
            return drumIDs.contains(event.key) ? nil : "鼓编号越界"
        case .parameter:
            guard let parameter = PerformanceParameter(rawValue: UInt8(clamping: event.key)) else {
                return "未知参数"
            }
            guard let value = event.value else { return "参数缺少值" }
            return parameter.range.contains(value) ? nil : "参数值越界"
        case .allNotesOff:
            return nil
        }
    }

    static let requiredEvents: [String] = [
        "note_on / note_off：钢琴 0–15 键、吉他 6 弦 + 品位，携带 token、力度、八度/品位",
        "chord_trigger：U/I/O/P 三音和弦，携带 token、和弦 ID、力度",
        "drum_trigger：小键盘 1–9 对应九鼓，携带 token、力度；闭镲 choke 由 FPGA/协议处理",
        "parameter_set：力度、八度、品位、和弦、总音量；开关发送目标状态；连续值可合并",
        "all_notes_off：离开页面、切模式、后台、全部停止时发送",
        "status/capability：协议版本、固件身份、支持乐器/键位、活动音符数、队列/错误状态"
    ]
}

struct PerformanceProtocolProfile {
    let isConfigured: Bool
    let version: String?
    let noteOnCommand: UInt8?
    let noteOffCommand: UInt8?
    let drumCommand: UInt8?
    let parameterCommand: UInt8?
    let allNotesOffCommand: UInt8?
    let capabilityCommand: UInt8?

    static let pending = PerformanceProtocolProfile(
        isConfigured: false,
        version: nil,
        noteOnCommand: nil,
        noteOffCommand: nil,
        drumCommand: nil,
        parameterCommand: nil,
        allNotesOffCommand: nil,
        capabilityCommand: nil
    )
}

protocol PerformanceEventEncoding {
    var profile: PerformanceProtocolProfile { get }
    func encode(_ event: PerformanceEvent) -> Data?
}

struct PendingPerformanceEventEncoding: PerformanceEventEncoding {
    let profile: PerformanceProtocolProfile = .pending

    func encode(_ event: PerformanceEvent) -> Data? {
        nil
    }
}