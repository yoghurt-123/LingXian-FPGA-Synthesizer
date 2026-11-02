import Foundation

enum PerformanceControl: String, CaseIterable, Identifiable, Equatable {
    case piano
    case drums
    case guitarPluck
    case chords
    case guitarFret
    case guitarPalm
    case bendVibrato
    case glideSlide
    case overdrive
    case reverb
    case pianoOctave
    case dampingPedal
    case releaseAll
    case allOff
    case sessionHeartbeat
    case query

    var id: String { rawValue }

    var bit: UInt32 {
        switch self {
        case .piano: return UInt32(1) << 0
        case .drums: return UInt32(1) << 1
        case .guitarPluck: return UInt32(1) << 2
        case .chords: return UInt32(1) << 3
        case .guitarFret: return UInt32(1) << 4
        case .guitarPalm: return UInt32(1) << 5
        case .bendVibrato: return UInt32(1) << 6
        case .glideSlide: return UInt32(1) << 7
        case .overdrive: return UInt32(1) << 8
        case .reverb: return UInt32(1) << 9
        case .pianoOctave: return UInt32(1) << 10
        case .dampingPedal: return UInt32(1) << 11
        case .releaseAll: return UInt32(1) << 12
        case .allOff: return UInt32(1) << 13
        case .sessionHeartbeat: return UInt32(1) << 14
        case .query: return UInt32(1) << 15
        }
    }

    var title: String {
        switch self {
        case .piano: return "钢琴"
        case .drums: return "九鼓"
        case .guitarPluck: return "吉他拨弦"
        case .chords: return "吉他和弦"
        case .guitarFret: return "吉他品位"
        case .guitarPalm: return "掌根闷音"
        case .bendVibrato: return "弯音/颤音"
        case .glideSlide: return "滑音/滑时"
        case .overdrive: return "吉他过载"
        case .reverb: return "吉他混响"
        case .pianoOctave: return "钢琴八度"
        case .dampingPedal: return "钢琴阻尼/踏板"
        case .releaseAll: return "BLE 全部释放"
        case .allOff: return "全局停止"
        case .sessionHeartbeat: return "会话/心跳"
        case .query: return "能力查询"
        }
    }

    static let baseInstrumentMask: UInt32 =
        PerformanceControl.piano.bit
        | PerformanceControl.drums.bit
        | PerformanceControl.guitarPluck.bit
}

enum CapabilityReplyFormat: String, Equatable {
    case legacyV1 = "FPGA_STATUS"
    case capsV2 = "CAPS"

    var title: String {
        switch self {
        case .legacyV1: return "旧版 FPGA_STATUS"
        case .capsV2: return "新版 CAPS"
        }
    }
}

struct PerformanceCapabilities: Equatable {
    let version: Int
    let mask: UInt32
    let status: UInt8
    let format: CapabilityReplyFormat

    static let baseInstrumentMask = PerformanceControl.baseInstrumentMask

    var isV1: Bool { version == 1 }
    var isV2: Bool { version == 2 }
    var supportsExtendedEvents: Bool { format == .capsV2 && (version == 2 || version == 3) }

    var statusOverflow: Bool { (status & 0x01) != 0 }
    var statusReserved: Bool { (status & 0xFE) != 0 }

    var hasBaseInstrument: Bool {
        if isV1 {
            return mask != 0
        }
        return (mask & Self.baseInstrumentMask) != 0
    }

    var isReady: Bool {
        guard !statusOverflow, !statusReserved, mask != 0, hasBaseInstrument else {
            return false
        }
        switch format {
        case .legacyV1:
            return version == 1
        case .capsV2:
            return supportsExtendedEvents
        }
    }

    func supports(_ control: PerformanceControl) -> Bool {
        guard isReady else { return false }
        if isV1 {
            switch control {
            case .piano, .drums, .guitarPluck, .releaseAll, .allOff, .sessionHeartbeat, .query:
                return true
            default:
                return false
            }
        }
        return (mask & control.bit) != 0
    }

    var supportedControls: [PerformanceControl] {
        PerformanceControl.allCases.filter { supports($0) }
    }

    var statusText: String {
        if format == .legacyV1, version != 1 {
            return "旧版回复版本 \(version) 异常"
        }
        if format == .capsV2, !supportsExtendedEvents {
            return "CAPS 版本 \(version) 不受支持"
        }
        if mask == 0 {
            return "能力掩码为空"
        }
        if !hasBaseInstrument {
            return "能力掩码未声明钢琴/九鼓/吉他拨弦"
        }
        if statusOverflow {
            return "FPGA 事件 FIFO/解析器溢出标志为 1，禁止演奏"
        }
        if statusReserved {
            return String(format: "状态保留位非零（0x%02X）", status)
        }
        let family = isV1 ? "v1 基础" : "v2 扩展"
        let names = supportedControls.filter {
            $0 != .sessionHeartbeat && $0 != .query
        }.map(\.title).joined(separator: "、")
        return "\(family)能力就绪 · mask 0x\(String(format: "%08X", mask)) · \(names)"
    }

    var summary: String {
        "\(format.rawValue) v\(version) · mask 0x\(String(format: "%08X", mask)) · status \(status)"
    }
}

enum CapabilityParseError: Error, Equatable {
    case empty
    case unknownPrefix
    case malformedFields
    case unsupportedVersion(Int)
    case versionFormatMismatch(format: CapabilityReplyFormat, version: Int)
    case invalidMask(String)
    case invalidStatus(String)
    case reservedStatus(UInt8)

    var message: String {
        switch self {
        case .empty:
            return "能力回复为空"
        case .unknownPrefix:
            return "未知能力回复前缀（需要 CAPS 或 FPGA_STATUS）"
        case .malformedFields:
            return "能力回复字段数量或格式错误"
        case .unsupportedVersion(let version):
            return "不支持的协议版本 \(version)"
        case .versionFormatMismatch(let format, let version):
            return "\(format.rawValue) 与版本 \(version) 不匹配"
        case .invalidMask(let value):
            return "能力掩码无效：\(value)"
        case .invalidStatus(let value):
            return "能力状态无效：\(value)"
        case .reservedStatus(let status):
            return String(format: "能力状态保留位非零：0x%02X", status)
        }
    }
}

enum CapabilityReplyParser {
    static func parse(_ text: String) -> Result<PerformanceCapabilities, CapabilityParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let format: CapabilityReplyFormat
        if trimmed.hasPrefix("CAPS;") {
            format = .capsV2
        } else if trimmed.hasPrefix("FPGA_STATUS;") {
            format = .legacyV1
        } else {
            return .failure(.unknownPrefix)
        }

        let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return .failure(.malformedFields) }
        guard let version = Int(parts[1]) else { return .failure(.malformedFields) }
        guard let mask = UInt32(parts[2], radix: 16) else {
            return .failure(.invalidMask(String(parts[2])))
        }
        guard let status = UInt8(parts[3]) else {
            return .failure(.invalidStatus(String(parts[3])))
        }

        switch format {
        case .legacyV1:
            guard version == 1 else {
                return .failure(.versionFormatMismatch(format: .legacyV1, version: version))
            }
        case .capsV2:
            guard version == 2 || version == 3 else {
                return .failure(.versionFormatMismatch(format: .capsV2, version: version))
            }
        }

        guard (status & 0xFE) == 0 else {
            return .failure(.reservedStatus(status))
        }

        return .success(
            PerformanceCapabilities(
                version: version,
                mask: mask,
                status: status,
                format: format
            )
        )
    }
}

enum PerformanceSlideTime {
    static let millisecondsPerStep = 20
    static let range: ClosedRange<Int> = 1...15

    static func milliseconds(for step: Int) -> Int {
        min(max(step, range.lowerBound), range.upperBound) * millisecondsPerStep
    }

    static func label(for step: Int) -> String {
        "\(step) 档 · \(milliseconds(for: step))ms"
    }
}

enum PerformanceBend: Int, CaseIterable, Identifiable, Equatable {
    case center = 0
    case left = 1
    case right = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .center: return "回中"
        case .left: return "左 -2"
        case .right: return "右 +2"
        }
    }
}

