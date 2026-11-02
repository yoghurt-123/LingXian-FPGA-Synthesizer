import Foundation
import CryptoKit

struct MusicHallE2Frame: Equatable {
    let type: UInt8
    let seq: UInt8
    let payload: Data
}

enum MusicHallE2Codec {
    // Frozen E2: CRC8 covers TYPE, SEQ, LEN and PAYLOAD. E2 is excluded.
    // Shared expected CAPS_RSP CRC for seq 0 is 0x4C.
    static func encode(type: UInt8, seq: UInt8, payload: Data) throws -> Data {
        guard payload.count <= 180 else {
            throw MusicHallError.protocolUnavailable("E2 payload 超过 180 字节")
        }
        var bytes: [UInt8] = [0xE2, type, seq, UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        bytes.append(crc8(bytes[1...]))
        return Data(bytes)
    }

    static func parse(_ data: Data) -> MusicHallE2Frame? {
        guard data.count >= 5, data[0] == 0xE2 else { return nil }
        let length = Int(data[3])
        guard length <= 180, data.count == length + 5 else { return nil }
        let payload = data.subdata(in: 4..<(4 + length))
        guard crc8(data[1..<(4 + length)]) == data[4 + length] else { return nil }
        return MusicHallE2Frame(type: data[1], seq: data[2], payload: payload)
    }

    static func crc8<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) : (crc << 1)
            }
        }
        return crc
    }
}

struct MusicHallE2Status: Equatable {
    let state: UInt8
    let code: UInt8
    let received: UInt32
    let stored: UInt32

    var isIdle: Bool { state == 0 }
    var isTransfer: Bool { state == 1 }
    // ESP transport state 2: PLAY was accepted and ESP is streaming toward
    // FPGA. This is not an FPGA execution acknowledgement.
    var isPlaying: Bool { state == 2 }
    var isStoredOrPrepared: Bool { state == 3 }
    var isEnded: Bool { state == 4 }
    var isError: Bool { state == 5 }
}

private struct MusicHallE2DeviceError: LocalizedError {
    let code: UInt8

    var errorDescription: String? {
        let detail: String
        switch code {
        case 1: detail = "帧格式/CRC 错误"
        case 2: detail = "设备未就绪"
        case 3: detail = "ESP→FPGA UART 发送失败"
        case 4: detail = "总长度/包大小非法"
        case 5: detail = "ESP 分配缓存失败"
        case 6: detail = "DATA 偏移/范围非法"
        case 7: detail = "上传不完整"
        case 8: detail = "SHA-256 不匹配"
        case 9: detail = "ESP 歌曲存储写入失败（不是 iPad 音乐包缓存；请重试或重启 ESP）"
        case 10: detail = "FPGS 头非法"
        case 11: detail = "PREPARE 失败"
        case 12: detail = "命令不支持"
        default: detail = "未知错误 \(code)"
        }
        return "设备音乐厅错误 \(code)：\(detail)"
    }
}

@MainActor
final class MusicHallBLETransport: MusicHallTransport {
    var onUpdate: ((MusicHallTransportUpdate) -> Void)?

    private weak var bluetooth: InstrumentBluetooth?
    private var nextSequence: UInt8 = 0
    private var pending: Pending?
    private var profile: MusicHallDeviceProfile?
    private var activeSession: UInt64 = 0

    private struct Pending {
        let seq: UInt8
        let acceptedTypes: Set<UInt8>
        let acceptsSequenceZero: Bool
        let continuation: CheckedContinuation<MusicHallE2Frame, Error>
        var timeoutTask: Task<Void, Never>?
    }

    init(bluetooth: InstrumentBluetooth) {
        self.bluetooth = bluetooth
        bluetooth.onMusicFrame = { [weak self] data in
            self?.handleFrame(data)
        }
    }

    func queryDevice() async throws -> MusicHallDeviceProfile {
        guard let bluetooth, bluetooth.isReady else {
            throw MusicHallError.protocolUnavailable("BLE 未连接或通知未就绪")
        }
        let response = try await sendCommand(
            type: 0x01,
            payload: Data(),
            acceptedTypes: [0x81],
            acceptsSequenceZero: false
        )
        guard response.type == 0x81, response.payload.count >= 9 else {
            throw MusicHallError.protocolUnavailable("CAPS_RSP 长度/类型错误")
        }
        let version = Int(response.payload[0])
        guard version >= 3 else {
            throw MusicHallError.protocolUnavailable("ESP/FPGA 音乐厅协议版本 \(version)，需要 3")
        }
        let mask = readLE32(response.payload, 1)
        let maxBytes = readLE32(response.payload, 5)
        guard maxBytes >= 32 else {
            throw MusicHallError.protocolUnavailable("ESP 返回的音乐包上限无效")
        }
        let profile = MusicHallDeviceProfile(
            protocolVersion: version,
            capabilityMask: mask,
            maxPackBytes: Int(maxBytes),
            maxChunkBytes: 180,
            supportsPiano: (mask & (UInt32(1) << 0)) != 0,
            supportsGuitar: (mask & (UInt32(1) << 2)) != 0,
            supportsDrums: (mask & (UInt32(1) << 1)) != 0,
            supportsTimedQueue: (mask & (UInt32(1) << 16)) != 0,
            supportsBulkTransfer: (mask & (UInt32(1) << 17)) != 0,
            supportsProgress: (mask & (UInt32(1) << 18)) != 0,
            supportsSongOwnedRelease: (mask & (UInt32(1) << 19)) != 0,
            supportsSongStop: true,
            supportsSeek: (mask & (UInt32(1) << 20)) != 0,
            supportsPause: false,
            supportsVolume: false
        )
        self.profile = profile
        return profile
    }

    func transfer(
        pack: MusicHallLocalPack,
        sessionID: UInt64,
        progress: @escaping (Double, MusicHallTransportPhase) -> Void
    ) async throws {
        guard let bluetooth, bluetooth.isReady else {
            throw MusicHallError.protocolUnavailable("BLE 未连接")
        }
        guard let profile else {
            throw MusicHallError.protocolUnavailable("未完成 CAPS 查询")
        }
        let performance = pack.performanceData
        guard performance.count >= 32,
              performance.count <= profile.maxPackBytes,
              performance.count <= 65_536 else {
            throw MusicHallError.device("performance.bin 超出 ESP 缓存上限")
        }
        guard let writeCapacity = bluetooth.musicWriteCapacity, writeCapacity >= 10 else {
            throw MusicHallError.device("当前 ATT MTU 无法发送 E2 音乐帧")
        }

        let maximumPayload = min(180, writeCapacity - 5)
        let chunkSize = min(128, maximumPayload - 4)
        guard chunkSize > 0 else {
            throw MusicHallError.device("当前 ATT MTU 无法容纳 DATA 偏移")
        }

        let session = UInt32(truncatingIfNeeded: sessionID)
        guard session != 0 else {
            throw MusicHallError.device("音乐厅 session ID 不能为 0")
        }
        let digest = Data(SHA256.hash(data: performance))

        // Frozen protocol v1: BEGIN is exactly 40 bytes:
        // session32, total_bytes32, performance_sha256[32], little-endian.
        // The same digest is sent again in COMMIT. BEGIN binds the transfer;
        // COMMIT proves the bytes actually received by ESP. There is no short
        // BEGIN and no length-based fallback.
        var mutableBegin = Data()
        appendLE32(&mutableBegin, session)
        appendLE32(&mutableBegin, UInt32(performance.count))
        mutableBegin.append(digest)
        guard mutableBegin.count == 40 else {
            throw MusicHallError.device("内部错误：BEGIN 不是 40 字节")
        }

        let beginResponse = try await sendCommand(
            type: 0x10,
            payload: mutableBegin,
            acceptedTypes: [0x96]
        )
        let beginStatus = try parseStatus(beginResponse)
        guard beginStatus.isTransfer, beginStatus.code == 0 else {
            throw MusicHallError.device("BEGIN 未进入 transfer 状态")
        }

        var offset = 0
        while offset < performance.count {
            let end = min(offset + chunkSize, performance.count)
            var data = Data()
            appendLE32(&data, UInt32(offset))
            data.append(performance.subdata(in: offset..<end))

            var lastError: Error?
            var received: UInt32 = 0
            for attempt in 0..<2 {
                do {
                    let response = try await sendCommand(
                        type: 0x11,
                        payload: data,
                        acceptedTypes: [0x96]
                    )
                    let status = try parseStatus(response)
                    guard status.isTransfer, status.code == 0 else {
                        throw MusicHallError.device("DATA 返回状态不是 transfer")
                    }
                    guard status.received >= UInt32(end) else {
                        throw MusicHallError.device("ESP 已接收字节少于本块结束位置")
                    }
                    received = status.received
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            }
            if let lastError { throw lastError }
            progress(Double(max(received, UInt32(end))) / Double(performance.count), .transferring)
            offset = end
        }

        let commitResponse = try await sendCommand(
            type: 0x12,
            payload: digest,
            acceptedTypes: [0x96]
        )
        let commitStatus = try parseStatus(commitResponse)
        guard commitStatus.isStoredOrPrepared, commitStatus.code == 0 else {
            throw MusicHallError.device("COMMIT 后设备未报告 stored/prepared")
        }
        progress(1, .verifying)
    }

    func prepare(pack: MusicHallLocalPack, sessionID: UInt64) async throws {
        let response = try await sendCommand(
            type: 0x13,
            payload: Data(),
            acceptedTypes: [0x96]
        )
        let status = try parseStatus(response)
        guard status.isStoredOrPrepared, status.code == 0 else {
            throw MusicHallError.device("PREPARE 未返回 stored/prepared")
        }
    }

    func play(pack: MusicHallLocalPack, sessionID: UInt64) async throws {
        activeSession = sessionID
        do {
            let response = try await sendCommand(
                type: 0x14,
                payload: Data([0]),
                acceptedTypes: [0x96],
                acceptsSequenceZero: false
            )
            let status = try parseStatus(response)
            guard status.isPlaying, status.code == 0 else {
                throw MusicHallError.device("ESP 未接受 PLAY/未进入流式发送")
            }
        } catch {
            activeSession = 0
            throw error
        }
    }

    func stop(sessionID: UInt64) async throws {
        let response = try await sendCommand(
            type: 0x15,
            payload: Data([1]),
            acceptedTypes: [0x96]
        )
        let status = try parseStatus(response)
        guard status.isIdle || status.isEnded, status.code == 0 else {
            throw MusicHallError.device("STOP 未返回 idle/ended")
        }
        activeSession = 0
    }

    func cancelTransfer(sessionID: UInt64) async {
        cancelPending()
        activeSession = 0
    }

    private func sendCommand(
        type: UInt8,
        payload: Data,
        acceptedTypes: Set<UInt8>,
        acceptsSequenceZero: Bool = false
    ) async throws -> MusicHallE2Frame {
        guard pending == nil else {
            throw MusicHallError.device("已有 E2 命令在等待回复")
        }
        guard let bluetooth else {
            throw MusicHallError.protocolUnavailable("BLE 对象已释放")
        }
        let seq = nextSequence
        nextSequence &+= 1
        let frame = try MusicHallE2Codec.encode(type: type, seq: seq, payload: payload)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MusicHallE2Frame, Error>) in
            var item = Pending(
                seq: seq,
                acceptedTypes: acceptedTypes.union(Set<UInt8>([0x97])),
                acceptsSequenceZero: acceptsSequenceZero,
                continuation: continuation,
                timeoutTask: nil
            )
            item.timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {
                    return
                }
                self?.finishPending(
                    .failure(MusicHallError.device("E2 \(String(format: "0x%02X", Int(type))) 回复超时")),
                    seq: seq
                )
            }
            pending = item
            bluetooth.writeMusicFrame(frame) { [weak self] result in
                if case .failure(let error) = result {
                    Task { @MainActor [weak self] in
                        self?.finishPending(.failure(error), seq: seq)
                    }
                }
            }
        }
    }

    private func handleFrame(_ data: Data) {
        guard let frame = MusicHallE2Codec.parse(data) else {
            return
        }

        if let pending {
            if frame.type == 0x97, frame.seq == pending.seq {
                let code = frame.payload.first ?? 12
                finishPending(.failure(MusicHallE2DeviceError(code: code)), seq: pending.seq)
                return
            }
            let sequenceMatches = frame.seq == pending.seq
                || (pending.acceptsSequenceZero && frame.seq == 0)
            if pending.acceptedTypes.contains(frame.type), sequenceMatches {
                finishPending(.success(frame), seq: pending.seq)
                return
            }
        }

        guard frame.type == 0x96 else { return }
        guard let status = try? parseStatus(frame) else { return }
        if status.isEnded {
            let session = activeSession
            activeSession = 0
            onUpdate?(.stopped(session: session))
        } else if status.isError {
            let session = activeSession
            activeSession = 0
            onUpdate?(.error("设备音乐厅状态错误 \(status.code)", session: session))
        }
    }

    private func parseStatus(_ frame: MusicHallE2Frame) throws -> MusicHallE2Status {
        if frame.type == 0x97 {
            throw MusicHallE2DeviceError(code: frame.payload.first ?? 12)
        }
        guard frame.type == 0x96, frame.payload.count >= 10 else {
            throw MusicHallError.device("STATUS 长度/类型错误")
        }
        let status = MusicHallE2Status(
            state: frame.payload[0],
            code: frame.payload[1],
            received: readLE32(frame.payload, 2),
            stored: readLE32(frame.payload, 6)
        )
        if status.code != 0 {
            throw MusicHallE2DeviceError(code: status.code)
        }
        return status
    }

    private func finishPending(_ result: Result<MusicHallE2Frame, Error>, seq: UInt8) {
        guard let item = pending, item.seq == seq else { return }
        pending = nil
        item.timeoutTask?.cancel()
        item.continuation.resume(with: result)
    }

    private func cancelPending() {
        guard let item = pending else { return }
        pending = nil
        item.timeoutTask?.cancel()
        item.continuation.resume(throwing: CancellationError())
    }
}

private func appendLE32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}

private func readLE32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
