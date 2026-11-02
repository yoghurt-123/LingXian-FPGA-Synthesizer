import Foundation

enum MusicHallPackOrigin: String, Codable {
    case online
    case imported

    var title: String {
        switch self {
        case .online: return "在线下载"
        case .imported: return "文件导入"
        }
    }
}

enum MusicHallTransportPhase: Equatable {
    case idle
    case checkingDevice
    case transferring
    case verifying
    case preparing
    case ready
    case starting
    case playing
    case stopping
    case stopped
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "未连接"
        case .checkingDevice: return "核对设备"
        case .transferring: return "传输到 ESP"
        case .verifying: return "设备校验"
        case .preparing: return "预装载"
        case .ready: return "ESP 已预装载"
        case .starting: return "等待 ESP PLAY 状态"
        case .playing: return "ESP 播放流（FPGA 无回执）"
        case .stopping: return "等待 ESP STOP 状态"
        case .stopped: return "ESP 已停止"
        case .failed(_): return "失败"
        }
    }
}

enum MusicHallDownloadPhase: Equatable {
    case idle
    case downloading
    case verifying
    case installing
    case cached
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "未下载"
        case .downloading: return "下载中"
        case .verifying: return "校验中"
        case .installing: return "写入 iPad"
        case .cached: return "已缓存到 iPad"
        case .failed(_): return "下载失败"
        }
    }
}

struct MusicHallDownloadProgress: Equatable {
    var phase: MusicHallDownloadPhase = .idle
    var fraction: Double = 0
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var message: String = ""
}

struct MusicHallTimeSignature: Codable, Equatable {
    let numerator: Int
    let denominator: Int
}

struct MusicHallTempo: Codable, Equatable {
    let tick: Int
    let bpm: Double
}

struct MusicHallScoreSection: Codable, Equatable, Identifiable {
    let startBar: Int
    let endBar: Int
    let title: String

    var id: String { "\(startBar)-\(endBar)-\(title)" }
}

struct MusicHallSourceInfo: Codable, Equatable {
    let name: String?
    let url: String?
    let author: String?
    let license: String?
    let licenseUrl: String?
    let published: String?
    let note: String?
}

struct MusicHallScoreInfo: Codable, Equatable {
    let schemaVersion: String?
    let songId: String
    let title: String
    let composer: String?
    let rights: String?
    let contentKind: String?
    let ppqn: Int?
    let timeSignature: MusicHallTimeSignature?
    let tempoMap: [MusicHallTempo]?
    let durationTicks: Int?
    let sections: [MusicHallScoreSection]?
    let source: MusicHallSourceInfo?

    var normalizedPPQN: Int {
        max(ppqn ?? 480, 1)
    }

    var normalizedTimeSignature: MusicHallTimeSignature {
        timeSignature ?? MusicHallTimeSignature(numerator: 4, denominator: 4)
    }

    var barLengthTicks: Double {
        let signature = normalizedTimeSignature
        let denominator = max(signature.denominator, 1)
        return Double(max(signature.numerator, 1)) * 4.0 / Double(denominator) * Double(normalizedPPQN)
    }

    func seconds(atTick tick: Int) -> TimeInterval {
        let tempo = (tempoMap ?? [MusicHallTempo(tick: 0, bpm: 120)])
            .sorted { $0.tick < $1.tick }
        guard let first = tempo.first else { return 0 }
        var seconds: TimeInterval = 0
        var previousTick = 0
        var previousBPM = max(first.bpm, 1)
        for segment in tempo where segment.tick > 0 {
            if tick <= segment.tick {
                break
            }
            let delta = segment.tick - previousTick
            seconds += Double(delta) * 60.0 / (previousBPM * Double(normalizedPPQN))
            previousTick = segment.tick
            previousBPM = max(segment.bpm, 1)
        }
        let remaining = max(tick - previousTick, 0)
        seconds += Double(remaining) * 60.0 / (previousBPM * Double(normalizedPPQN))
        return max(seconds, 0)
    }

    func startSeconds(forBar bar: Int) -> TimeInterval {
        let tick = Int((Double(max(bar - 1, 0)) * barLengthTicks).rounded())
        return seconds(atTick: tick)
    }

    func section(at time: TimeInterval) -> MusicHallScoreSection? {
        guard let sections, !sections.isEmpty else { return nil }
        var result = sections[0]
        for section in sections {
            let start = startSeconds(forBar: section.startBar)
            if time + 0.0001 >= start {
                result = section
            } else {
                break
            }
        }
        return result
    }
}

struct MusicHallStageSection: Codable, Equatable, Identifiable {
    let barStart: Int
    let barEnd: Int
    let title: String
    let activeTracks: [String]?
    let lightHint: String?

    var id: String { "\(barStart)-\(barEnd)-\(title)" }

    // JSONDecoder converts start_bar/end_bar to startBar/endBar.
    private enum CodingKeys: String, CodingKey {
        case barStart = "startBar"
        case barEnd = "endBar"
        case title
        case activeTracks
        case lightHint
    }
}

struct MusicHallStage: Codable, Equatable {
    let schemaVersion: String?
    let songId: String?
    let contentKind: String?
    let stageTitle: String?
    let visualStyle: String?
    let sections: [MusicHallStageSection]?
    let notes: [String]?
}

struct MusicHallManifestTarget: Codable, Equatable {
    let sampleRateNum: Int?
    let sampleRateDen: Int?
    let sampleRateHz: Double?
    let ppqn: Int?
    let firmwareSupport: String?
}

struct MusicHallManifestFile: Codable, Equatable {
    let bytes: Int64
    let sha256: String
}

struct MusicHallManifest: Codable, Equatable {
    let format: String
    let formatVersion: String
    let songId: String
    let title: String
    let composer: String?
    let rights: String?
    let contentKind: String?
    let created: String?
    let source: MusicHallSourceInfo?
    let target: MusicHallManifestTarget?
    let capabilitiesRequired: [String]?
    let files: [String: MusicHallManifestFile]
    let compileReport: String?
    let limitations: [String]?
}

struct MusicHallCatalogSong: Codable, Identifiable, Equatable {
    let songId: String
    let title: String
    let artist: String
    let durationSeconds: Double?
    let sourceName: String?
    let sourceUrl: String?
    let license: String?
    let licenseUrl: String?
    let arrangement: String?
    let coverUrl: String?
    let packUrl: String?
    let file: String?
    let relativePath: String?
    let packBytes: Int64?
    let packSha256: String?
    let formatVersion: String?
    let requiredCapabilities: [String]?

    var id: String { songId }
    var coverURL: URL? {
        guard let coverUrl else { return nil }
        return URL(string: coverUrl)
    }

    var resolvedSourceName: String {
        if let sourceName, !sourceName.isEmpty { return sourceName }
        if let sourceUrl, sourceUrl.lowercased().contains("opengameart.org") {
            return "OpenGameArt"
        }
        return "在线曲库"
    }

    init(
        songId: String,
        title: String,
        artist: String,
        durationSeconds: Double?,
        sourceName: String?,
        sourceUrl: String?,
        license: String?,
        licenseUrl: String?,
        arrangement: String?,
        coverUrl: String?,
        packUrl: String?,
        packBytes: Int64?,
        packSha256: String?,
        formatVersion: String?,
        requiredCapabilities: [String]?,
        file: String? = nil,
        relativePath: String? = nil
    ) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.license = license
        self.licenseUrl = licenseUrl
        self.arrangement = arrangement
        self.coverUrl = coverUrl
        self.packUrl = packUrl
        self.file = file
        self.relativePath = relativePath
        self.packBytes = packBytes
        self.packSha256 = packSha256
        self.formatVersion = formatVersion
        self.requiredCapabilities = requiredCapabilities
    }

    func resolvedPackURL(catalogURL: URL?) -> URL? {
        if let packUrl, !packUrl.isEmpty {
            if let absolute = URL(string: packUrl), absolute.scheme != nil {
                return absolute
            }
            if let catalogURL {
                return resolveRelative(packUrl, against: catalogURL)
            }
        }
        guard let catalogURL else { return nil }
        if let file, !file.isEmpty {
            return catalogURL.deletingLastPathComponent().appendingPathComponent(file)
        }
        if let relativePath, !relativePath.isEmpty {
            return resolveRelative(relativePath, against: catalogURL)
        }
        return nil
    }

    private func resolveRelative(_ raw: String, against catalogURL: URL) -> URL? {
        guard let baseDirectory = URL(string: catalogURL.absoluteString)?.deletingLastPathComponent() else {
            return nil
        }
        let first = raw.split(separator: "/").first.map(String.init)
        if first == baseDirectory.lastPathComponent {
            var components = URLComponents(url: catalogURL, resolvingAgainstBaseURL: false)
            components?.path = "/"
            components?.query = nil
            components?.fragment = nil
            if let root = components?.url {
                return URL(string: raw, relativeTo: root)?.absoluteURL
            }
        }
        return URL(string: raw, relativeTo: baseDirectory)?.absoluteURL
    }

    private enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case id
        case title
        case artist
        case composer
        case durationSeconds = "duration_seconds"
        case sourceName = "source_name"
        case sourceUrl = "source_url"
        case license
        case licenseUrl = "license_url"
        case arrangement
        case coverUrl = "cover_url"
        case cover
        case packUrl = "pack_url"
        case file
        case relativePath = "relative_path"
        case packBytes = "pack_bytes"
        case bytes
        case packSha256 = "pack_sha256"
        case sha256
        case formatVersion = "format_version"
        case requiredCapabilities = "required_capabilities"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songId = try (container.decodeIfPresent(String.self, forKey: .songId)
            ?? container.decode(String.self, forKey: .id))
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名曲目"
        artist = try (container.decodeIfPresent(String.self, forKey: .artist)
            ?? container.decodeIfPresent(String.self, forKey: .composer)
            ?? "未知作者")
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        licenseUrl = try container.decodeIfPresent(String.self, forKey: .licenseUrl)
        arrangement = try container.decodeIfPresent(String.self, forKey: .arrangement)
        coverUrl = try (container.decodeIfPresent(String.self, forKey: .coverUrl)
            ?? container.decodeIfPresent(String.self, forKey: .cover))
        packUrl = try container.decodeIfPresent(String.self, forKey: .packUrl)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        packBytes = try (container.decodeIfPresent(Int64.self, forKey: .packBytes)
            ?? container.decodeIfPresent(Int64.self, forKey: .bytes))
        packSha256 = try (container.decodeIfPresent(String.self, forKey: .packSha256)
            ?? container.decodeIfPresent(String.self, forKey: .sha256))
        formatVersion = try container.decodeIfPresent(String.self, forKey: .formatVersion)
        requiredCapabilities = try container.decodeIfPresent([String].self, forKey: .requiredCapabilities)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(songId, forKey: .songId)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encodeIfPresent(licenseUrl, forKey: .licenseUrl)
        try container.encodeIfPresent(arrangement, forKey: .arrangement)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(packUrl, forKey: .packUrl)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(packBytes, forKey: .packBytes)
        try container.encodeIfPresent(packSha256, forKey: .packSha256)
        try container.encodeIfPresent(formatVersion, forKey: .formatVersion)
        try container.encodeIfPresent(requiredCapabilities, forKey: .requiredCapabilities)
    }
}
struct MusicHallCatalog: Codable, Equatable {
    let schemaVersion: String?
    let generatedAt: String?
    let songs: [MusicHallCatalogSong]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case songs
    }
}

enum MusicHallSeedCatalog {
    static let rockTheme3 = MusicHallCatalogSong(
        songId: "rock-theme-3-full-cc0",
        title: "Rock Theme 3",
        artist: "Umplix",
        durationSeconds: 64.98750415238095,
        sourceName: "OpenGameArt",
        sourceUrl: "https://opengameart.org/content/rock-theme-3",
        license: "CC0 1.0",
        licenseUrl: "https://creativecommons.org/publicdomain/zero/1.0/",
        arrangement: "钢琴承担主 riff，吉他提供低音/节奏，九鼓承担原曲鼓组；没有原唱，不编造歌词。",
        coverUrl: nil,
        packUrl: nil,
        packBytes: nil,
        packSha256: nil,
        formatVersion: "0.1",
        requiredCapabilities: ["piano", "guitar-pluck", "drums", "timed-event-queue", "bulk-song-transfer", "song-owned-stop"]
    )

    static let songs: [MusicHallCatalogSong] = [rockTheme3]
}

struct MusicHallSong: Identifiable {
    let catalog: MusicHallCatalogSong?
    let local: MusicHallLocalPack?
    let catalogBaseURL: URL?

    var id: String {
        local?.id ?? catalog?.songId ?? "unknown"
    }

    var title: String {
        local?.title ?? catalog?.title ?? "未命名曲目"
    }

    var artist: String {
        local?.artist ?? catalog?.artist ?? "未知作者"
    }

    var durationSeconds: Double {
        local?.durationSeconds ?? catalog?.durationSeconds ?? 0
    }

    var sourceName: String {
        local?.sourceName ?? catalog?.resolvedSourceName ?? "来源未注明"
    }

    var arrangement: String? {
        local?.arrangement ?? catalog?.arrangement
    }

    var isCached: Bool { local != nil }
    var downloadURL: URL? { catalog?.resolvedPackURL(catalogURL: catalogBaseURL) }
    var requiredCapabilities: [String] {
        local?.requiredCapabilities ?? catalog?.requiredCapabilities ?? []
    }
}

enum MusicHallInstrument: String, CaseIterable, Identifiable, Hashable {
    case piano
    case guitar
    case drums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .piano: return "钢琴"
        case .guitar: return "吉他"
        case .drums: return "鼓"
        }
    }
}

enum MusicHallEventKind: UInt8, Equatable {
    case pianoOn = 1
    case pianoOff = 2
    case drum = 3
    case guitarPluck = 4
    case guitarChord = 5
    case parameter = 6
    case releaseAll = 7
    case allOff = 8

    var instrument: MusicHallInstrument? {
        switch self {
        case .pianoOn, .pianoOff: return .piano
        case .drum: return .drums
        case .guitarPluck, .guitarChord: return .guitar
        default: return nil
        }
    }

    var isCue: Bool {
        switch self {
        case .pianoOn, .drum, .guitarPluck, .guitarChord: return true
        default: return false
        }
    }
}

struct MusicHallPerformanceEvent: Equatable, Identifiable {
    let id: Int
    let timeSamples: UInt32
    let typeRaw: UInt8
    let a: UInt8
    let b: UInt8
    let flags: UInt8
    let time: TimeInterval

    var kind: MusicHallEventKind? { MusicHallEventKind(rawValue: typeRaw) }
    var instrument: MusicHallInstrument? { kind?.instrument }
    var isCue: Bool { kind?.isCue == true }
    var velocity: Int {
        switch kind {
        case .pianoOn, .drum, .guitarPluck, .guitarChord:
            return Int(b)
        default:
            return 0
        }
    }
}

struct MusicHallPerformance: Equatable {
    let sampleRateNumerator: UInt32
    let sampleRateDenominator: UInt16
    let eventCount: Int
    let durationSamples: UInt32
    let eventCRC32: UInt32
    let songIDHash: UInt32
    let events: [MusicHallPerformanceEvent]

    var durationSeconds: TimeInterval {
        guard sampleRateDenominator > 0 else { return 0 }
        return Double(durationSamples) * Double(sampleRateDenominator) / Double(sampleRateNumerator)
    }

    var cueEvents: [MusicHallPerformanceEvent] {
        events.filter(\.isCue)
    }

    static func parse(_ data: Data) throws -> MusicHallPerformance {
        guard data.count >= 32 else {
            throw MusicHallError.invalidPack("performance.bin 小于 32 字节头")
        }
        guard data[0] == 0x46, data[1] == 0x50, data[2] == 0x47, data[3] == 0x53 else {
            throw MusicHallError.invalidPack("performance.bin 缺少 FPGS magic")
        }
        guard data[4] == 1 else {
            throw MusicHallError.invalidPack("performance.bin 版本不是 1")
        }
        guard data[5] == 32 else {
            throw MusicHallError.invalidPack("performance.bin header size 不是 32")
        }
        guard data[6] == 8 else {
            throw MusicHallError.invalidPack("performance.bin event size 不是 8")
        }
        let sampleNum = readUInt32(data, 8)
        let sampleDen = readUInt16(data, 12)
        let eventCount = Int(readUInt32(data, 16))
        let durationSamples = readUInt32(data, 20)
        let crc = readUInt32(data, 24)
        let songHash = readUInt32(data, 28)

        guard sampleNum > 0, sampleDen > 0 else {
            throw MusicHallError.invalidPack("performance.bin 采样率无效")
        }
        guard eventCount > 0, eventCount <= 250_000 else {
            throw MusicHallError.invalidPack("performance.bin 事件数超出范围")
        }
        let expectedSize = 32 + eventCount * 8
        guard data.count == expectedSize else {
            throw MusicHallError.invalidPack("performance.bin 长度与事件数不一致")
        }

        var records = [UInt8]()
        records.reserveCapacity(eventCount * 8)
        var events: [MusicHallPerformanceEvent] = []
        events.reserveCapacity(eventCount)
        var previousSample: UInt32 = 0
        for index in 0..<eventCount {
            let base = 32 + index * 8
            let time = readUInt32(data, base)
            let type = data[base + 4]
            let a = data[base + 5]
            let b = data[base + 6]
            let flags = data[base + 7]
            records.append(contentsOf: data[base..<(base + 8)])

            guard time <= durationSamples + 1 else {
                throw MusicHallError.invalidPack("performance.bin 事件时间超出歌曲时长")
            }
            guard time >= previousSample else {
                throw MusicHallError.invalidPack("performance.bin 事件时间未排序")
            }
            previousSample = time
            guard let kind = MusicHallEventKind(rawValue: type) else {
                throw MusicHallError.invalidPack("performance.bin 存在未知事件类型 \(type)")
            }
            try validateEvent(kind: kind, a: a, b: b)
            let seconds = Double(time) * Double(sampleDen) / Double(sampleNum)
            events.append(
                MusicHallPerformanceEvent(
                    id: index,
                    timeSamples: time,
                    typeRaw: type,
                    a: a,
                    b: b,
                    flags: flags,
                    time: seconds
                )
            )
        }

        let calculatedCRC = MusicHallCRC32.checksum(records)
        guard calculatedCRC == crc else {
            throw MusicHallError.invalidPack("performance.bin CRC32 不匹配")
        }

        return MusicHallPerformance(
            sampleRateNumerator: sampleNum,
            sampleRateDenominator: sampleDen,
            eventCount: eventCount,
            durationSamples: durationSamples,
            eventCRC32: crc,
            songIDHash: songHash,
            events: events
        )
    }

    private static func validateEvent(kind: MusicHallEventKind, a: UInt8, b: UInt8) throws {
        switch kind {
        case .pianoOn:
            guard a < 16, (1...15).contains(b) else {
                throw MusicHallError.invalidPack("performance.bin 钢琴事件范围错误")
            }
        case .pianoOff:
            guard a < 16 else {
                throw MusicHallError.invalidPack("performance.bin 钢琴释放范围错误")
            }
        case .drum:
            guard a < 9, (1...15).contains(b) else {
                throw MusicHallError.invalidPack("performance.bin 鼓事件范围错误")
            }
        case .guitarPluck:
            guard a < 6, (1...15).contains(b), (b & 0xF0) == 0 else {
                throw MusicHallError.invalidPack("performance.bin 吉他事件范围错误")
            }
        case .guitarChord:
            guard a < 4, (1...15).contains(b) else {
                throw MusicHallError.invalidPack("performance.bin 和弦事件范围错误")
            }
        case .parameter:
            guard a <= 6 else {
                throw MusicHallError.invalidPack("performance.bin 参数字段范围错误")
            }
        case .releaseAll, .allOff:
            break
        }
    }
}

struct MusicHallLocalPack: Identifiable {
    let id: String
    let manifest: MusicHallManifest
    let score: MusicHallScoreInfo
    let stage: MusicHallStage?
    let performance: MusicHallPerformance
    let performanceData: Data
    let directoryURL: URL
    let coverData: Data?
    let origin: MusicHallPackOrigin
    let installedAt: Date
    let archiveSHA256: String?
    let archiveBytes: Int64?

    var title: String { score.title.isEmpty ? manifest.title : score.title }
    var artist: String { score.composer ?? manifest.composer ?? "未知作者" }
    var sourceName: String {
        let sourceURLText = score.source?.url ?? manifest.source?.url
        if let sourceURLText, sourceURLText.lowercased().contains("opengameart.org") {
            return "OpenGameArt"
        }
        return score.source?.name ?? manifest.source?.name
            ?? (manifest.contentKind == "licensed-score" ? "授权曲目" : "项目测试曲目")
    }
    var sourceURL: URL? {
        let raw = score.source?.url ?? manifest.source?.url
        guard let raw else { return nil }
        return URL(string: raw)
    }
    var arrangement: String? {
        score.source?.note ?? manifest.source?.note
    }
    var durationSeconds: TimeInterval { performance.durationSeconds }
    var requiredCapabilities: [String] {
        manifest.capabilitiesRequired ?? []
    }
    var sections: [MusicHallScoreSection] {
        if let stageSections = stage?.sections, !stageSections.isEmpty {
            return stageSections.map {
                MusicHallScoreSection(startBar: $0.barStart, endBar: $0.barEnd, title: $0.title)
            }
        }
        return score.sections ?? []
    }
    var contentKind: String { manifest.contentKind ?? score.contentKind ?? "unknown" }
    var isLicensed: Bool { contentKind == "licensed-score" }
}

enum MusicHallError: LocalizedError {
    case invalidPack(String)
    case invalidArchive(String)
    case unsafePath(String)
    case tooLarge(String)
    case missingFile(String)
    case digestMismatch(String)
    case network(String)
    case protocolUnavailable(String)
    case device(String)

    var errorDescription: String? {
        switch self {
        case .invalidPack(let message): return "歌曲包校验失败：\(message)"
        case .invalidArchive(let message): return "歌曲包解压失败：\(message)"
        case .unsafePath(let path): return "歌曲包包含不安全路径：\(path)"
        case .tooLarge(let message): return "歌曲包超出限制：\(message)"
        case .missingFile(let name): return "歌曲包缺少文件：\(name)"
        case .digestMismatch(let name): return "歌曲包摘要不匹配：\(name)"
        case .network(let message): return "网络错误：\(message)"
        case .protocolUnavailable(let message): return "设备协议不可用：\(message)"
        case .device(let message): return "设备状态：\(message)"
        }
    }
}

enum MusicHallCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        checksum([UInt8](data))
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

func musicHallDurationText(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

