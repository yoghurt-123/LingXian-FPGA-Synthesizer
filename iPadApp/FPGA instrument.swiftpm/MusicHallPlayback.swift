import Foundation

struct MusicHallDeviceProfile: Equatable {
    let protocolVersion: Int
    let capabilityMask: UInt32
    let maxPackBytes: Int
    let maxChunkBytes: Int
    let supportsPiano: Bool
    let supportsGuitar: Bool
    let supportsDrums: Bool
    let supportsTimedQueue: Bool
    let supportsBulkTransfer: Bool
    let supportsProgress: Bool
    let supportsSongOwnedRelease: Bool
    let supportsSongStop: Bool
    let supportsSeek: Bool
    let supportsPause: Bool
    let supportsVolume: Bool

    func missingRequirements(for pack: MusicHallLocalPack) -> [String] {
        var missing: [String] = []
        for requirement in pack.requiredCapabilities {
            switch requirement {
            case "piano":
                if !supportsPiano { missing.append("钢琴") }
            case "guitar", "guitar-pluck":
                if !supportsGuitar { missing.append("吉他") }
            case "drums":
                if !supportsDrums { missing.append("鼓") }
            case "timed-event-queue":
                if !supportsTimedQueue { missing.append("定时事件队列") }
            case "bulk-song-transfer", "bulk-performance-transfer":
                if !supportsBulkTransfer { missing.append("歌曲传输") }
            case "progress-report":
                if !supportsProgress { missing.append("播放进度") }
            case "song-owned-release":
                if !supportsSongOwnedRelease { missing.append("歌曲释放") }
            case "song-owned-stop":
                if !supportsSongStop { missing.append("歌曲停止") }
            default:
                missing.append(requirement)
            }
        }
        return missing
    }
}

struct MusicHallSessionGate {
    private(set) var generation: UInt64 = 0
    private(set) var activeHardware: Bool = false
    private(set) var startConfirmed: Bool = false
    private(set) var stopUnconfirmed: Bool = false

    mutating func beginHardwareSession() -> UInt64 {
        generation &+= 1
        activeHardware = true
        startConfirmed = false
        stopUnconfirmed = false
        return generation
    }

    @discardableResult
    mutating func confirmStart(_ session: UInt64) -> Bool {
        guard activeHardware, session == generation else { return false }
        startConfirmed = true
        return true
    }

    func acceptsProgress(_ session: UInt64) -> Bool {
        activeHardware && startConfirmed && session == generation
    }

    var canEnterFreePlay: Bool {
        !activeHardware && !stopUnconfirmed
    }

    mutating func requestStop() {
        startConfirmed = false
    }

    mutating func stopSucceeded() {
        activeHardware = false
        startConfirmed = false
        stopUnconfirmed = false
    }

    mutating func stopFailed() {
        activeHardware = true
        startConfirmed = false
        stopUnconfirmed = true
    }

    mutating func disconnect() {
        startConfirmed = false
        if activeHardware {
            stopUnconfirmed = true
        }
    }
}

enum MusicHallTransportUpdate {
    case progress(TimeInterval, session: UInt64)
    case state(MusicHallTransportPhase, session: UInt64)
    case stopped(session: UInt64)
    case error(String, session: UInt64)
}

@MainActor
protocol MusicHallTransport: AnyObject {
    var onUpdate: ((MusicHallTransportUpdate) -> Void)? { get set }
    func queryDevice() async throws -> MusicHallDeviceProfile
    func transfer(
        pack: MusicHallLocalPack,
        sessionID: UInt64,
        progress: @escaping (Double, MusicHallTransportPhase) -> Void
    ) async throws
    func prepare(pack: MusicHallLocalPack, sessionID: UInt64) async throws
    func play(pack: MusicHallLocalPack, sessionID: UInt64) async throws
    func stop(sessionID: UInt64) async throws
    func cancelTransfer(sessionID: UInt64) async
}

enum MusicHallPlaybackMode: Equatable {
    case none
    case fpga
    case stagePreview

    var title: String {
        switch self {
        case .none: return "未播放"
        case .fpga: return "ESP 流式发送（FPGA 无回执）"
        case .stagePreview: return "舞台预览（静音）"
        }
    }
}

@MainActor
final class MusicHallController: ObservableObject {
    @Published private(set) var phase: MusicHallTransportPhase = .idle
    @Published private(set) var mode: MusicHallPlaybackMode = .none
    @Published private(set) var activePack: MusicHallLocalPack?
    @Published private(set) var deviceProfile: MusicHallDeviceProfile?
    @Published private(set) var transferFraction: Double = 0
    @Published private(set) var transferMessage: String = "尚未开始传输"
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published private(set) var stopUnconfirmed = false
    @Published private(set) var statusMessage: String = "音乐厅传输适配器已装载；ESP 状态与 FPGA 执行分开显示"

    private var transport: MusicHallTransport?
    private var anchorPosition: TimeInterval = 0
    private var anchorHostTime: TimeInterval?
    private var previewStartedAt: TimeInterval?
    private var previewAccumulated: TimeInterval = 0
    private var operationID: Int = 0
    private var sessionGate = MusicHallSessionGate()
    private var currentSession: UInt64 = 0

    var hasSession: Bool {
        mode != .none || phase == .checkingDevice || phase == .transferring
            || phase == .verifying || phase == .preparing || phase == .ready
            || phase == .starting || phase == .playing || phase == .stopping
            || sessionGate.activeHardware || stopUnconfirmed
    }

    var hasHardwarePlayback: Bool {
        mode == .fpga && (phase == .starting || phase == .playing || phase == .stopping)
    }

    var blocksFreePlay: Bool {
        stopUnconfirmed || sessionGate.activeHardware || mode == .fpga || !sessionGate.canEnterFreePlay
    }

    var playbackClockIsEstimated: Bool {
        mode == .fpga && !(deviceProfile?.supportsProgress ?? false)
    }

    var playbackClockTitle: String {
        if mode == .stagePreview { return "预览时钟" }
        if mode == .fpga {
            return playbackClockIsEstimated ? "估算动画（无硬件进度）" : "设备进度"
        }
        return "未播放"
    }

    var presentationLabel: String {
        if mode == .stagePreview {
            return "静音舞台预览"
        }
        if mode == .fpga {
            if stopUnconfirmed {
                return "FPGA 停止未确认"
            }
            switch phase {
            case .starting:
                return "等待 ESP PLAY 状态"
            case .playing:
                return "ESP 流式发送（FPGA 无回执）"
            case .stopping:
                return "等待 ESP 停止状态"
            case .failed(_):
                return "音乐厅播放失败"
            default:
                return "ESP 音乐厅"
            }
        }
        return phase.title
    }

    var canUseHardware: Bool {
        transport != nil
    }

    func attach(transport: MusicHallTransport?) {
        self.transport = transport
        transport?.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.handle(update)
            }
        }
        statusMessage = transport == nil
            ? "硬件协议未冻结；当前只能下载、缓存、导入和舞台静音预览"
            : "设备协议适配器已装载，等待能力核对"
    }

    func prepareForHardware(_ pack: MusicHallLocalPack) {
        guard let transport else {
            phase = .failed("硬件协议未冻结；不能开始 FPGA 演奏")
            lastError = "App 不会把本地预览冒充 FPGA 声音"
            statusMessage = lastError ?? ""
            return
        }
        guard !hasSession, !stopUnconfirmed else { return }
        let operation = beginOperation()
        currentSession = sessionGate.beginHardwareSession()
        stopUnconfirmed = false
        activePack = pack
        mode = .fpga
        playbackDuration = pack.durationSeconds
        playbackPosition = 0
        anchorPosition = 0
        anchorHostTime = nil
        transferFraction = 0
        transferMessage = "核对设备能力"
        lastError = nil
        phase = .checkingDevice
        statusMessage = "正在核对设备协议、定时播放与缓存能力"

        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(operation) else { return }
            do {
                let profile = try await transport.queryDevice()
                guard self.isCurrent(operation) else { return }
                self.deviceProfile = profile
                let missing = profile.missingRequirements(for: pack)
                guard missing.isEmpty else {
                    throw MusicHallError.device("缺少：\(missing.joined(separator: "、"))")
                }
                self.phase = .transferring
                self.transferMessage = "传输演奏数据"
                try await transport.transfer(pack: pack, sessionID: self.currentSession) { fraction, phase in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrent(operation) else { return }
                        self.transferFraction = min(max(fraction, 0), 1)
                        self.phase = phase
                        self.transferMessage = phase.title
                    }
                }
                guard self.isCurrent(operation) else { return }
                self.phase = .preparing
                self.transferMessage = "等待设备预装载确认"
                try await transport.prepare(pack: pack, sessionID: self.currentSession)
                guard self.isCurrent(operation) else { return }
                self.phase = .ready
                self.transferFraction = 1
                self.transferMessage = "设备已就绪"
                self.statusMessage = "ESP 已确认缓存和预装载；FPGA 执行无回执"
            } catch {
                guard self.isCurrent(operation) else { return }
                self.fail(error)
            }
        }
    }

    func startHardwarePlayback() {
        guard let pack = activePack, let transport, sessionGate.activeHardware else {
            fail(MusicHallError.protocolUnavailable("没有可用的已确认设备会话"))
            return
        }
        guard phase == .ready else {
            lastError = "设备尚未完成校验和预装载"
            return
        }
        let operation = beginOperation()
        let session = currentSession
        lastError = nil
        mode = .fpga
        phase = .starting
        playbackPosition = 0
        anchorPosition = 0
        anchorHostTime = nil
        transferMessage = "已发送 PLAY，等待 ESP 状态"
        statusMessage = "等待 ESP 接受 PLAY；该状态不是 FPGA 执行确认"

        Task { @MainActor [weak self] in
            do {
                try await transport.play(pack: pack, sessionID: session)
                guard let self, self.isCurrent(operation) else { return }
                guard self.sessionGate.confirmStart(session) else {
                    throw MusicHallError.device("ESP 接受 PLAY 与当前会话不匹配")
                }
                self.phase = .playing
                self.playbackPosition = 0
                self.anchorPosition = 0
                self.anchorHostTime = ProcessInfo.processInfo.systemUptime
                self.transferMessage = "ESP 已进入流式发送"
                self.statusMessage = self.playbackClockIsEstimated
                    ? "ESP 已接受 PLAY 并开始流式发送；FPGA 执行无回执，该候选无硬件进度，时间轴是明确标注的估算动画"
                    : "ESP 已接受 PLAY；进度来自设备回传"
            } catch {
                guard let self, self.isCurrent(operation) else { return }
                self.fail(error)
            }
        }
    }

    func startStagePreview(_ pack: MusicHallLocalPack) {
        guard mode != .fpga, phase != .stopping, !hasSession else { return }
        activePack = pack
        playbackDuration = pack.durationSeconds
        playbackPosition = 0
        previewAccumulated = 0
        previewStartedAt = ProcessInfo.processInfo.systemUptime
        mode = .stagePreview
        phase = .playing
        lastError = nil
        statusMessage = "静音舞台预览：只演示段落、乐手与灯光，不产生 FPGA 声音"
    }

    func stop(completion: @escaping () -> Void = {}) {
        guard hasSession else {
            completion()
            return
        }
        guard phase != .stopping else { return }
        let previousMode = mode
        let previousPhase = phase
        let session = currentSession
        let operation = beginOperation()
        if previousMode == .fpga {
            sessionGate.requestStop()
        }
        phase = .stopping
        statusMessage = previousMode == .fpga ? "正在等待设备停止确认" : "正在停止预览"
        anchorHostTime = nil
        previewStartedAt = nil
        if previousMode == .stagePreview {
            mode = .none
        }

        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(operation) else { return }
            if previousMode == .fpga {
                guard let transport = self.transport else {
                    guard self.isCurrent(operation) else { return }
                    self.handleStopFailure(MusicHallError.protocolUnavailable("没有可用的停止通道"))
                    return
                }
                if previousPhase == .checkingDevice || previousPhase == .transferring
                    || previousPhase == .verifying || previousPhase == .preparing
                    || previousPhase == .starting {
                    await transport.cancelTransfer(sessionID: session)
                }
                do {
                    try await transport.stop(sessionID: session)
                } catch {
                    guard self.isCurrent(operation) else { return }
                    self.handleStopFailure(error)
                    return
                }
            }
            guard self.isCurrent(operation) else { return }
            if previousMode == .fpga {
                self.sessionGate.stopSucceeded()
                self.stopUnconfirmed = false
            }
            self.phase = .stopped
            self.mode = .none
            self.playbackPosition = 0
            self.anchorPosition = 0
            self.transferFraction = 0
            self.transferMessage = "已停止"
            self.statusMessage = previousMode == .fpga
                ? "ESP 已报告 STOP 状态；FPGA 执行无回执，旧会话不会自动续发"
                : "舞台预览已停止"
            completion()
        }
    }

    func handleBackground() {
        guard hasSession else { return }
        statusMessage = "App 进入后台：停止当前会话，不在后台续发"
        stop()
    }

    func handleDisconnect() {
        guard hasSession || deviceProfile != nil || sessionGate.activeHardware || stopUnconfirmed else { return }
        _ = beginOperation()
        let hadHardware = sessionGate.activeHardware || mode == .fpga || stopUnconfirmed
        let session = currentSession
        if let transport, phase == .checkingDevice || phase == .transferring
            || phase == .verifying || phase == .preparing || phase == .starting {
            Task { await transport.cancelTransfer(sessionID: session) }
        }
        sessionGate.disconnect()
        stopUnconfirmed = sessionGate.stopUnconfirmed
        if hadHardware {
            mode = .fpga
            phase = .failed("BLE 断线：ESP/FPGA 停止未确认，禁止进入自由演奏")
            statusMessage = "BLE 断线；ESP/FPGA 停止未确认，自由演奏仍被阻止"
        } else {
            mode = .none
            phase = .failed("BLE 断线；当前音乐厅会话已作废")
            statusMessage = "BLE 断线；未完成传输和播放不会自动恢复"
        }
        lastError = "连接中断，需重新核对设备能力；旧会话不会自动恢复"
        anchorHostTime = nil
        previewStartedAt = nil
        playbackPosition = 0
        transferFraction = 0
        transferMessage = "断线，状态未确认"
        deviceProfile = nil
    }

    private func handleStopFailure(_ error: Error) {
        sessionGate.stopFailed()
        stopUnconfirmed = true
        mode = .fpga
        phase = .failed("停止未确认：\(error.localizedDescription)")
        lastError = error.localizedDescription
        statusMessage = "停止失败：旧会话可能仍在发声；已阻止自由演奏"
        transferMessage = "停止未确认"
        transferFraction = 0
        anchorHostTime = nil
    }

    private func beginOperation() -> Int {
        operationID += 1
        return operationID
    }

    private func isCurrent(_ operation: Int) -> Bool {
        operationID == operation
    }

    func displayTime(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        switch mode {
        case .stagePreview:
            if phase == .playing, let previewStartedAt {
                return min(max(previewAccumulated + now - previewStartedAt, 0), playbackDuration)
            }
            return min(max(previewAccumulated, 0), playbackDuration)
        case .fpga:
            if phase == .playing, let anchorHostTime {
                return min(max(anchorPosition + now - anchorHostTime, 0), playbackDuration)
            }
            return min(max(anchorPosition, 0), playbackDuration)
        case .none:
            return min(max(playbackPosition, 0), playbackDuration)
        }
    }

    func progress(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        guard playbackDuration > 0 else { return 0 }
        return min(max(displayTime(now: now) / playbackDuration, 0), 1)
    }

    private func handle(_ update: MusicHallTransportUpdate) {
        switch update {
        case .progress(let time, let session):
            guard session == currentSession,
                  sessionGate.acceptsProgress(session),
                  mode == .fpga,
                  phase == .playing else { return }
            let safe = min(max(time, 0), playbackDuration)
            playbackPosition = safe
            anchorPosition = safe
            anchorHostTime = ProcessInfo.processInfo.systemUptime
        case .state(let state, let session):
            guard session == currentSession else { return }
            if case .failed(let message) = state {
                fail(MusicHallError.device(message))
                return
            }
            if state == .playing, !sessionGate.startConfirmed {
                return
            }
            if state == .stopped {
                sessionGate.stopSucceeded()
                stopUnconfirmed = false
                mode = .none
                anchorHostTime = nil
                playbackPosition = 0
                statusMessage = "ESP 已报告 STOP 状态；FPGA 执行无回执"
                phase = .stopped
                return
            }
            phase = state
            if state == .playing, anchorHostTime == nil {
                anchorPosition = max(playbackPosition, 0)
                anchorHostTime = ProcessInfo.processInfo.systemUptime
            }
        case .stopped(let session):
            guard session == currentSession else { return }
            sessionGate.stopSucceeded()
            stopUnconfirmed = false
            phase = .stopped
            mode = .none
            anchorHostTime = nil
            playbackPosition = 0
            statusMessage = "ESP 已报告 STOP 状态；FPGA 执行无回执"
        case .error(let message, let session):
            guard session == currentSession else { return }
            fail(MusicHallError.device(message))
        }
    }

    private func fail(_ error: Error) {
        if sessionGate.activeHardware {
            sessionGate.stopFailed()
            stopUnconfirmed = true
            mode = .fpga
            transferMessage = "设备会话未确认停止"
            statusMessage = "失败：\(error.localizedDescription)；旧会话可能仍未停止，禁止自由演奏"
        } else {
            mode = .none
            stopUnconfirmed = false
            transferMessage = "失败"
            statusMessage = error.localizedDescription
        }
        phase = .failed(error.localizedDescription)
        lastError = error.localizedDescription
        anchorHostTime = nil
        previewStartedAt = nil
        playbackPosition = 0
        transferFraction = 0
    }
}