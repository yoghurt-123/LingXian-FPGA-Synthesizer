import Foundation

enum MusicHallSimulator {
    static func run() -> [PerformanceSimTest] {
        [
            seedMetadataTest(),
            performanceHeaderTest(),
            unsafeZipPathTest(),
            capabilityGateTest(),
            startConfirmationTest(),
            stopFailureTest(),
            disconnectSessionTest(),
            oldSessionReplyTest(),
            catalogV1ParsingTest(),
            e2VectorTest()
        ]
    }

    private static func seedMetadataTest() -> PerformanceSimTest {
        let song = MusicHallSeedCatalog.rockTheme3
        let passed = song.title == "Rock Theme 3"
            && song.artist == "Umplix"
            && song.packUrl == nil
            && song.file == nil
            && song.license == "CC0 1.0"
            && (song.requiredCapabilities ?? []).contains("timed-event-queue")
        return PerformanceSimTest(
            title: "音乐厅首曲目录",
            detail: passed
                ? "Rock Theme 3 / Umplix / 无占位在线包地址"
                : "首曲元数据或未配置下载状态不正确",
            passed: passed
        )
    }

    private static func performanceHeaderTest() -> PerformanceSimTest {
        let event: [UInt8] = [0, 0, 0, 0, 1, 0, 10, 0]
        let eventData = Data(event)
        var data = Data()
        data.append(contentsOf: [0x46, 0x50, 0x47, 0x53])
        data.append(1)
        data.append(32)
        data.append(8)
        data.append(0)
        appendUInt32(&data, 52_500_000)
        appendUInt16(&data, 1088)
        appendUInt16(&data, 0)
        appendUInt32(&data, 1)
        appendUInt32(&data, 100)
        appendUInt32(&data, MusicHallCRC32.checksum(eventData))
        appendUInt32(&data, 0)
        data.append(eventData)
        let parsed = try? MusicHallPerformance.parse(data)
        let passed = parsed?.eventCount == 1
            && parsed?.events.first?.kind == .pianoOn
            && (parsed?.durationSeconds ?? 0) > 0
        return PerformanceSimTest(
            title: "音乐厅 FPGS 头与 CRC",
            detail: passed ? "事件头、CRC、绝对样本时间可解析" : "FPGS 头或事件 CRC 解析失败",
            passed: passed
        )
    }

    private static func unsafeZipPathTest() -> PerformanceSimTest {
        let zip = makeStoredZip(entries: [("../evil", Data("x".utf8))])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicHallTest-\(UUID().uuidString)", isDirectory: true)
        var rejected = false
        do {
            try MusicHallArchive.extract(archive: zip, to: destination)
        } catch {
            rejected = true
        }
        try? FileManager.default.removeItem(at: destination)
        return PerformanceSimTest(
            title: "音乐厅 ZIP 路径安全",
            detail: rejected ? "拒绝 ../ 越界路径" : "越界 ZIP 路径未被拒绝",
            passed: rejected
        )
    }

    private static func capabilityGateTest() -> PerformanceSimTest {
        let pack = fakePack()
        let profile = MusicHallDeviceProfile(
            protocolVersion: 0,
            capabilityMask: 0,
            maxPackBytes: 0,
            maxChunkBytes: 0,
            supportsPiano: true,
            supportsGuitar: true,
            supportsDrums: true,
            supportsTimedQueue: false,
            supportsBulkTransfer: true,
            supportsProgress: false,
            supportsSongOwnedRelease: false,
            supportsSongStop: true,
            supportsSeek: false,
            supportsPause: false,
            supportsVolume: false
        )
        let missing = profile.missingRequirements(for: pack)
        let passed = missing.contains("定时事件队列")
            && missing.contains("播放进度")
            && missing.contains("歌曲释放")
            && !missing.contains("钢琴")
        return PerformanceSimTest(
            title: "音乐厅能力门禁",
            detail: passed ? "缺少定时队列/进度/释放时不允许演奏" : "能力门禁漏判",
            passed: passed
        )
    }

    private static func catalogV1ParsingTest() -> PerformanceSimTest {
        let json = """
        {
          "schema_version": "1.0",
          "channel": { "kind": "static-local-and-lan", "public_url": null },
          "songs": [{
            "song_id": "rock-theme-3-full-cc0",
            "title": "Rock Theme 3 full song",
            "composer": "Umplix",
            "license": "CC0-1.0",
            "source_url": "https://opengameart.org/content/rock-theme-3",
            "duration_seconds": 64.9875,
            "file": "rock_theme_3_full.fpgasong",
            "relative_path": "music_packs/rock_theme_3_full.fpgasong",
            "bytes": 17681,
            "sha256": "893f01477b0bbdf117e24ff9b55abf25518b48c4697d8eaee48af59276e2871a",
            "cover": null,
            "minimum": { "protocol": "music-hall-v1", "fpga_protocol_version": 3 }
          }]
        }
        """
        let catalog = try? MusicHallPackValidator.catalogDecoder.decode(
            MusicHallCatalog.self,
            from: Data(json.utf8)
        )
        let song = catalog?.songs.first
        let catalogURL = URL(string: "http://127.0.0.1:8081/music_packs/catalog.json")!
        let resolved = song?.resolvedPackURL(catalogURL: catalogURL)?.absoluteString
        let expected = "http://127.0.0.1:8081/music_packs/rock_theme_3_full.fpgasong"
        let passed = song?.songId == "rock-theme-3-full-cc0"
            && song?.artist == "Umplix"
            && song?.packBytes == 17681
            && song?.packSha256?.lowercased() == "893f01477b0bbdf117e24ff9b55abf25518b48c4697d8eaee48af59276e2871a"
            && song?.resolvedSourceName == "OpenGameArt"
            && resolved == expected
        return PerformanceSimTest(
            title: "音乐厅曲库 v1 字段/相对地址",
            detail: passed
                ? "composer/file/bytes/sha256 统一解析，相对包地址解析正确"
                : "v1 曲库字段或相对地址解析失败",
            passed: passed
        )
    }

    private static func e2VectorTest() -> PerformanceSimTest {
        let capsRequest = try? MusicHallE2Codec.encode(type: 0x01, seq: 0x00, payload: Data())
        let capsPayload = Data([3, 0xFF, 0xFF, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00])
        let capsResponse = try? MusicHallE2Codec.encode(type: 0x81, seq: 0x00, payload: capsPayload)
        let digest = Data(musicHallHex: "23C822E15D0D3D35D678F37DCBC3F14A999CA111557F82A14B7188D5895B7737") ?? Data()
        var beginPayload = Data([0x44, 0x33, 0x22, 0x11, 0x00, 0x2C, 0x00, 0x00])
        beginPayload.append(digest)
        let begin = try? MusicHallE2Codec.encode(type: 0x10, seq: 0x01, payload: beginPayload)
        let event: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 4, 0x0C, 0x20]
        let data = try? MusicHallE2Codec.encode(type: 0x11, seq: 0x02, payload: Data(event))
        let commit = try? MusicHallE2Codec.encode(type: 0x12, seq: 0x02, payload: digest)
        let status = try? MusicHallE2Codec.encode(
            type: 0x96, seq: 0x01,
            payload: Data([1, 0, 0, 0, 0, 0, 0, 0x2C, 0, 0])
        )
        let error = try? MusicHallE2Codec.encode(type: 0x97, seq: 0x03, payload: Data([8]))
        let stop = try? MusicHallE2Codec.encode(type: 0x15, seq: 0x04, payload: Data([0x01]))
        let playStatus = try? MusicHallE2Codec.encode(
            type: 0x96, seq: 0x05,
            payload: Data([2, 0, 0, 0x2C, 0, 0, 0, 0x2C, 0, 0])
        )
        let parsedCaps = capsResponse.flatMap(MusicHallE2Codec.parse)
        let parsedBegin = begin.flatMap(MusicHallE2Codec.parse)
        let parsedPlay = playStatus.flatMap(MusicHallE2Codec.parse)
        let passed = capsRequest?.musicHallHex == "E20100006B"
            && capsResponse?.musicHallHex == "E281000903FFFF0300000001004C"
            && begin?.musicHallHex == "E210012844332211002C000023C822E15D0D3D35D678F37DCBC3F14A999CA111557F82A14B7188D5895B77376E"
            && data?.musicHallHex == "E211020C000000000000000001040C205A"
            && commit?.musicHallHex == "E212022023C822E15D0D3D35D678F37DCBC3F14A999CA111557F82A14B7188D5895B7737C3"
            && status?.musicHallHex == "E296010A010000000000002C0000B5"
            && error?.musicHallHex == "E297030108A4"
            && stop?.musicHallHex == "E21504010190"
            && playStatus?.musicHallHex == "E296050A0200002C0000002C000040"
            && parsedCaps?.payload == capsPayload
            && parsedBegin?.type == 0x10
            && parsedBegin?.seq == 0x01
            && parsedPlay?.payload.first == 0x02
        return PerformanceSimTest(
            title: "音乐厅 E2 双向共享向量",
            detail: passed
                ? "CAPS/STATUS/ERROR/PLAY/STOP 与 App 编解码一致"
                : "E2 请求/回复帧或 CRC 与冻结向量不一致",
            passed: passed
        )
    }

    private static func startConfirmationTest() -> PerformanceSimTest {
        var gate = MusicHallSessionGate()
        let session = gate.beginHardwareSession()
        let before = gate.acceptsProgress(session)
        let confirmed = gate.confirmStart(session)
        let after = gate.acceptsProgress(session)
        let passed = !before && confirmed && after
        return PerformanceSimTest(
            title: "音乐厅开始确认门禁",
            detail: passed
                ? "设备确认开始前不接收播放进度"
                : "开始确认门禁失败",
            passed: passed
        )
    }

    private static func stopFailureTest() -> PerformanceSimTest {
        var gate = MusicHallSessionGate()
        let session = gate.beginHardwareSession()
        _ = gate.confirmStart(session)
        gate.requestStop()
        gate.stopFailed()
        let failedBlocked = gate.activeHardware
            && gate.stopUnconfirmed
            && !gate.startConfirmed
            && !gate.acceptsProgress(session)
            && !gate.canEnterFreePlay
        gate.stopSucceeded()
        let recovered = gate.canEnterFreePlay && !gate.stopUnconfirmed
        let passed = failedBlocked && recovered
        return PerformanceSimTest(
            title: "音乐厅停止失败门禁",
            detail: passed
                ? "停止失败保留旧会话并阻止自由演奏；确认停止后才恢复"
                : "停止失败被误判为已停止",
            passed: passed
        )
    }

    private static func disconnectSessionTest() -> PerformanceSimTest {
        var gate = MusicHallSessionGate()
        let session = gate.beginHardwareSession()
        _ = gate.confirmStart(session)
        gate.disconnect()
        let passed = gate.stopUnconfirmed
            && !gate.startConfirmed
            && !gate.acceptsProgress(session)
            && !gate.canEnterFreePlay
        return PerformanceSimTest(
            title: "音乐厅断线会话门禁",
            detail: passed
                ? "断线后旧会话仍标记为停止未确认"
                : "断线后错误放行旧会话",
            passed: passed
        )
    }

    private static func oldSessionReplyTest() -> PerformanceSimTest {
        var gate = MusicHallSessionGate()
        let oldSession = gate.beginHardwareSession()
        let newSession = gate.beginHardwareSession()
        let oldConfirm = gate.confirmStart(oldSession)
        let newConfirm = gate.confirmStart(newSession)
        let acceptedOld = gate.acceptsProgress(oldSession)
        let acceptedNew = gate.acceptsProgress(newSession)
        let passed = !oldConfirm && newConfirm && !acceptedOld && acceptedNew
        return PerformanceSimTest(
            title: "音乐厅旧会话回复",
            detail: passed
                ? "旧 session 的开始/进度回复被拒绝"
                : "旧 session 回复仍被接受",
            passed: passed
        )
    }

    private static func fakePack() -> MusicHallLocalPack {
        let manifest = MusicHallManifest(
            format: "fpgasong",
            formatVersion: "0.1",
            songId: "test-song",
            title: "Test",
            composer: "Test",
            rights: nil,
            contentKind: "licensed-score",
            created: nil,
            source: nil,
            target: nil,
            capabilitiesRequired: [
                "piano", "timed-event-queue", "progress-report", "song-owned-release"
            ],
            files: [:],
            compileReport: nil,
            limitations: nil
        )
        let score = MusicHallScoreInfo(
            schemaVersion: "0.1",
            songId: "test-song",
            title: "Test",
            composer: "Test",
            rights: nil,
            contentKind: "licensed-score",
            ppqn: 480,
            timeSignature: MusicHallTimeSignature(numerator: 4, denominator: 4),
            tempoMap: [MusicHallTempo(tick: 0, bpm: 120)],
            durationTicks: 480,
            sections: [],
            source: nil
        )
        let performance = MusicHallPerformance(
            sampleRateNumerator: 52_500_000,
            sampleRateDenominator: 1088,
            eventCount: 1,
            durationSamples: 100,
            eventCRC32: 0,
            songIDHash: 0,
            events: []
        )
        return MusicHallLocalPack(
            id: "test-song",
            manifest: manifest,
            score: score,
            stage: nil,
            performance: performance,
            performanceData: Data(),
            directoryURL: URL(fileURLWithPath: "/tmp/test-song"),
            coverData: nil,
            origin: .imported,
            installedAt: Date(),
            archiveSHA256: nil,
            archiveBytes: nil
        )
    }

    private static func makeStoredZip(entries: [(String, Data)]) -> Data {
        var local = Data()
        var central = Data()
        var offsets: [Int] = []
        for (name, payload) in entries {
            let nameData = Data(name.utf8)
            let crc = MusicHallCRC32.checksum(payload)
            offsets.append(local.count)
            appendUInt32(&local, 0x04034B50)
            appendUInt16(&local, 20)
            appendUInt16(&local, 0)
            appendUInt16(&local, 0)
            appendUInt16(&local, 0)
            appendUInt16(&local, 0)
            appendUInt32(&local, crc)
            appendUInt32(&local, UInt32(payload.count))
            appendUInt32(&local, UInt32(payload.count))
            appendUInt16(&local, UInt16(nameData.count))
            appendUInt16(&local, 0)
            local.append(nameData)
            local.append(payload)
        }
        for (index, entry) in entries.enumerated() {
            let nameData = Data(entry.0.utf8)
            let payload = entry.1
            appendUInt32(&central, 0x02014B50)
            appendUInt16(&central, 20)
            appendUInt16(&central, 20)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt32(&central, MusicHallCRC32.checksum(payload))
            appendUInt32(&central, UInt32(payload.count))
            appendUInt32(&central, UInt32(payload.count))
            appendUInt16(&central, UInt16(nameData.count))
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt32(&central, 0)
            appendUInt32(&central, UInt32(offsets[index]))
            central.append(nameData)
        }
        let centralOffset = local.count
        var zip = local
        zip.append(central)
        appendUInt32(&zip, 0x06054B50)
        appendUInt16(&zip, 0)
        appendUInt16(&zip, 0)
        appendUInt16(&zip, UInt16(entries.count))
        appendUInt16(&zip, UInt16(entries.count))
        appendUInt32(&zip, UInt32(central.count))
        appendUInt32(&zip, UInt32(centralOffset))
        appendUInt16(&zip, 0)
        return zip
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
private extension Data {
    init?(musicHallHex: String) {
        guard musicHallHex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = musicHallHex.startIndex
        while index < musicHallHex.endIndex {
            let next = musicHallHex.index(index, offsetBy: 2)
            guard let byte = UInt8(musicHallHex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    var musicHallHex: String {
        map { String(format: "%02X", Int($0)) }.joined()
    }
}