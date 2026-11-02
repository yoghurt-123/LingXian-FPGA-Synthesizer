import Foundation
import Combine
import CoreBluetooth

// All CoreBluetooth callbacks and published UI state use the main queue.
// v0.12.0 accepts both legacy FPGA_STATUS v1 and CAPS v2 capability replies.
final class InstrumentBluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, PerformanceEventSink {
    struct Device: Identifiable {
        let id: UUID
        var name: String
        var rssi: Int
    }
    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }
    private struct Request {
        let command: String
        let sent: TimeInterval
    }
    @Published private(set) var status = "尚未启动蓝牙"
    @Published private(set) var devices: [Device] = []
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isConnecting = false
    @Published private(set) var fpgaVerified = false
    @Published private(set) var performanceReady = false
    @Published private(set) var performanceProtocolStatus = "等待 BLE 连接与演奏能力查询"
    @Published private(set) var performanceQueueDepth = 0
    @Published private(set) var performanceDropped = 0
    @Published private(set) var performanceRejected = 0
    @Published private(set) var performanceLastError = "—"
    @Published private(set) var capabilityVersion: Int? = nil
    @Published private(set) var capabilityMask: UInt32? = nil
    @Published private(set) var capabilityStatus: UInt8? = nil
    @Published private(set) var capabilityReplyFormat: CapabilityReplyFormat? = nil
    @Published private(set) var negotiatedCapabilities: PerformanceCapabilities? = nil
    @Published private(set) var performanceGroupDepth = 0
    @Published private(set) var sessionID = 0
    @Published private(set) var lastReply = "尚无回复"
    @Published private(set) var roundTrip = "—"

    private let serviceID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var request: Request?
    private var deadline: DispatchWorkItem?
    private var scanDeadline: DispatchWorkItem?
    private var connectionDeadline: DispatchWorkItem?
    private var wantScan = false
    private let performanceQueue = PerformanceCommandQueue(limit: 16)
    private var capabilityQueryPending = false
    private var capabilityDeadline: DispatchWorkItem?
    private var performanceWriteInFlight = false
    private var performanceInFlightPacket: PerformanceQueuePacket?
    private var performanceInFlightGroupProtected = false
    private var sessionGeneration = 0
    private var lastPerformanceLog = 0.0
    private var lastPerformanceLogMessage = ""
    var onMusicFrame: ((Data) -> Void)?
    private var lastPerformanceSubmitUptime = 0.0
    private var musicWriteInFlight = false
    private var musicWriteCompletion: ((Result<Void, Error>) -> Void)?
    private var musicWriteDeadline: DispatchWorkItem?

    var musicWriteCapacity: Int? {
        guard isReady, let target = peripheral, let rx = rx,
              rx.properties.contains(.write) else { return nil }
        return target.maximumWriteValueLength(for: .withResponse)
    }

    var shortStatus: String {
        if isPerformanceSinkAvailable {
            if let capabilities = negotiatedCapabilities {
                return capabilities.isV1 ? "BLE · FPGA v1 基础演奏" : "BLE · FPGA v2 表达演奏"
            }
            return "BLE · FPGA 演奏就绪"
        }
        if isReady {
            return "BLE 诊断连接 · 演奏能力未确认"
        }
        return status
    }

    var isPerformanceSinkAvailable: Bool {
        isReady && performanceReady && negotiatedCapabilities != nil && rx != nil
    }

    var performanceCapabilities: PerformanceCapabilities? {
        negotiatedCapabilities
    }

    var performanceSinkDescription: String {
        if !isReady { return "BLE 未连接或通知未订阅" }
        if negotiatedCapabilities == nil { return "等待 CAPS / FPGA_STATUS 能力回复" }
        if !performanceReady { return negotiatedCapabilities?.statusText ?? "演奏能力未确认" }
        return negotiatedCapabilities?.isV1 == true ? "FPGA v1 基础演奏已就绪" : "FPGA v2 扩展演奏已就绪"
    }

    func supports(_ control: PerformanceControl) -> Bool {
        negotiatedCapabilities?.supports(control) ?? false
    }

    private func log(_ text: String) {
        logs.append(LogEntry(text: text))
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
    }

    private func logThrottled(_ text: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if text == lastPerformanceLogMessage, now - lastPerformanceLog < 2.0 {
            return
        }
        lastPerformanceLog = now
        lastPerformanceLogMessage = text
        log(text)
    }

    func clearLogs() { logs.removeAll() }

    func scan() {
        guard !isConnecting, peripheral == nil else { return }
        wantScan = true
        if central == nil {
            status = "正在请求蓝牙权限"
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            status = "请开启蓝牙并允许本 App 使用蓝牙"
        }
    }

    private func beginScan() {
        guard let central = central, central.state == .poweredOn else { return }
        scanDeadline?.cancel()
        devices.removeAll()
        peripherals.removeAll()
        central.scanForPeripherals(withServices: [serviceID], options: nil)
        isScanning = true
        status = "正在搜索 FPGA-Instrument"
        log("扫描目标服务；请先断开 nRF Connect")
        let work = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func stopScan() {
        wantScan = false
        scanDeadline?.cancel()
        central?.stopScan()
        isScanning = false
        if peripheral == nil {
            status = devices.isEmpty ? "未发现设备；检查 ESP 供电或其他 App 的连接" : "请选择设备连接"
        }
    }

    func connect(_ id: UUID) {
        guard let target = peripherals[id], let central = central,
              central.state == .poweredOn, peripheral == nil else { return }
        stopScan()
        resetLink()
        peripheral = target
        target.delegate = self
        isConnecting = true
        status = "正在连接"
        log("连接 \(target.name ?? "FPGA-Instrument")")
        central.connect(target, options: nil)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isReady else { return }
            self.fail("连接或服务发现超时，请重试")
        }
        connectionDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func disconnect() {
        stopScan()
        if let target = peripheral { central?.cancelPeripheralConnection(target) }
        resetLink()
        status = "已断开"
        log("主动断开；本地演奏继续使用本地音色")
    }

    func resetConnection() {
        disconnect()
        devices.removeAll()
        peripherals.removeAll()
        wantScan = false
        lastReply = "尚未通信"
        roundTrip = "—"
        performanceLastError = "—"
        status = "蓝牙会话已重置；请重新扫描连接"
        log("重置 App 侧蓝牙会话；不会清除 ESP NVS 歌曲缓存")
    }

    func suspend() {
        if isReady && performanceReady && (performanceQueue.count > 0 || performanceWriteInFlight) {
            logThrottled("后台前尝试刷新保护释放包")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                if self.isScanning || self.peripheral != nil {
                    self.disconnect()
                }
            }
            return
        }
        if isScanning || peripheral != nil { disconnect() }
    }

    private func resetLink() {
        if musicWriteInFlight {
            musicWriteInFlight = false
            musicWriteDeadline?.cancel()
            musicWriteDeadline = nil
            let completion = musicWriteCompletion
            musicWriteCompletion = nil
            completion?(.failure(MusicHallError.device("BLE 链接已重置，E2 写入未完成")))
        }
        deadline?.cancel()
        connectionDeadline?.cancel()
        request = nil
        rx = nil
        tx = nil
        isReady = false
        isBusy = false
        isConnecting = false
        fpgaVerified = false
        performanceReady = false
        performanceWriteInFlight = false
        performanceInFlightPacket = nil
        performanceInFlightGroupProtected = false
        capabilityQueryPending = false
        capabilityDeadline?.cancel()
        capabilityDeadline = nil
        capabilityVersion = nil
        capabilityMask = nil
        capabilityStatus = nil
        capabilityReplyFormat = nil
        negotiatedCapabilities = nil
        performanceQueue.clearAll()
        performanceQueueDepth = 0
        performanceGroupDepth = 0
        performanceProtocolStatus = "等待 BLE 连接与演奏能力查询"
        sessionGeneration &+= 1
        sessionID = sessionGeneration
    }

    func writeMusicFrame(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isReady, let target = peripheral, let rx = rx,
              rx.properties.contains(.write) else {
            completion(.failure(MusicHallError.device("BLE 未连接或 RX 不支持可靠写入")))
            return
        }
        guard !musicWriteInFlight else {
            completion(.failure(MusicHallError.device("已有 E2 写入在等待 ATT 确认")))
            return
        }
        guard !performanceWriteInFlight, performanceQueue.isEmpty else {
            completion(.failure(MusicHallError.device("自由演奏发送队列未清空，不能开始音乐厅传输")))
            return
        }
        guard data.count <= target.maximumWriteValueLength(for: .withResponse) else {
            completion(.failure(MusicHallError.device("E2 帧超过当前 ATT MTU")))
            return
        }
        musicWriteInFlight = true
        musicWriteCompletion = completion
        target.writeValue(data, for: rx, type: .withResponse)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.musicWriteInFlight else { return }
            self.musicWriteInFlight = false
            self.musicWriteDeadline = nil
            let completion = self.musicWriteCompletion
            self.musicWriteCompletion = nil
            completion?(.failure(MusicHallError.device("E2 写入 ATT 确认超时")))
        }
        musicWriteDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func finishMusicWrite(_ result: Result<Void, Error>) {
        guard musicWriteInFlight else { return }
        musicWriteInFlight = false
        musicWriteDeadline?.cancel()
        musicWriteDeadline = nil
        let completion = musicWriteCompletion
        musicWriteCompletion = nil
        completion?(result)
    }

    private func fail(_ message: String) {
        log(message)
        status = message
        if let target = peripheral { central?.cancelPeripheralConnection(target) }
        resetLink()
        // Keep the peripheral retained until the disconnect callback arrives.
    }

    func submitPerformanceGroup(_ group: PerformancePacketGroup) -> Bool {
        guard isReady else {
            performanceLastError = "BLE 未连接或通知未订阅"
            return false
        }
        guard performanceReady, negotiatedCapabilities != nil else {
            performanceLastError = "演奏能力未确认"
            performanceProtocolStatus = "等待 CAPS / FPGA_STATUS 能力回复"
            logThrottled("未发送演奏组：演奏能力未确认")
            return false
        }
        guard !group.packets.isEmpty else {
            performanceLastError = "演奏组为空"
            return false
        }
        guard group.packetCount <= performanceQueue.limit else {
            performanceLastError = "演奏组超过队列上限，整组拒绝"
            return false
        }

        if group.clearsPending {
            performanceQueue.removeAllNonProtected()
        }
        let accepted = performanceQueue.enqueueGroup(group.withSession(sessionGeneration))
        updateQueueMetrics()
        if accepted { lastPerformanceSubmitUptime = ProcessInfo.processInfo.systemUptime }
        if !accepted {
            performanceLastError = "发送队列不足；整组未发送，未留下孤立触发"
            logThrottled("演奏组被拒绝：容量不足，保持参数/触发整组原子性")
            return false
        }
        if performanceQueue.droppedCount > 0 {
            logThrottled("发送队列背压：整组丢弃最旧非保护组")
        }
        drainPerformanceQueue()
        return true
    }

    private func updateQueueMetrics() {
        performanceQueueDepth = performanceQueue.count
        performanceGroupDepth = performanceQueue.groupCount
        performanceDropped = performanceQueue.droppedCount
        performanceRejected = performanceQueue.rejectedCount
    }

    private func drainPerformanceQueue() {
        guard isReady, performanceReady, !performanceWriteInFlight,
              let target = peripheral, let rx = rx else {
            updateQueueMetrics()
            return
        }

        while let packet = performanceQueue.peekPacket() {
            guard rx.properties.contains(.write) || rx.properties.contains(.writeWithoutResponse) else {
                performanceLastError = "RX 特征不可写"
                break
            }
            let useWithoutResponse = rx.properties.contains(.writeWithoutResponse)
                && target.canSendWriteWithoutResponse
            let writeType: CBCharacteristicWriteType = useWithoutResponse ? .withoutResponse : .withResponse
            let maxLength = target.maximumWriteValueLength(for: writeType)
            guard packet.data.count <= maxLength else {
                if performanceQueue.frontGroupIsProtected {
                    performanceLastError = "保护包超过当前 MTU，保留未发送"
                    logThrottled("保护包超过当前 MTU，队列保留")
                    break
                }
                _ = performanceQueue.dequeuePacket()
                performanceLastError = "演奏包超过当前 MTU"
                logThrottled("演奏包超过当前 MTU，已丢弃")
                updateQueueMetrics()
                continue
            }

            if useWithoutResponse {
                _ = performanceQueue.dequeuePacket()
                target.writeValue(packet.data, for: rx, type: .withoutResponse)
                updateQueueMetrics()
                if !target.canSendWriteWithoutResponse { break }
            } else {
                if !rx.properties.contains(.write) {
                    performanceLastError = "RX 特征不支持 withResponse"
                    break
                }
                performanceInFlightGroupProtected = performanceQueue.frontGroupIsProtected
                _ = performanceQueue.dequeuePacket()
                performanceWriteInFlight = true
                performanceInFlightPacket = packet
                target.writeValue(packet.data, for: rx, type: .withResponse)
                performanceQueueDepth = performanceQueue.count + 1
                performanceGroupDepth = performanceQueue.groupCount
                break
            }
        }
    }

    func sendTest(_ command: String) {
        guard ["PING", "FPGA_PING", "STATUS"].contains(command),
              isReady, !isBusy, let target = peripheral, let rx = rx else { return }
        guard !performanceWriteInFlight, performanceQueue.isEmpty else {
            logThrottled("演奏发送期间暂停诊断，避免 ACK 串扰")
            return
        }
        guard let data = command.data(using: .utf8),
              data.count <= target.maximumWriteValueLength(for: .withResponse) else {
            log("指令超出当前写入长度")
            return
        }
        if command == "FPGA_PING" { fpgaVerified = false }
        request = Request(command: command, sent: ProcessInfo.processInfo.systemUptime)
        isBusy = true
        roundTrip = "等待回复"
        log("发送 \(command)")
        target.writeValue(data, for: rx, type: .withResponse)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.request != nil else { return }
            self.roundTrip = "> 3000 ms（超时）"
            // Disconnect after timeout: plain PONG has no request ID, so a late
            // response must not be attributed to the next request.
            self.fail("3 秒内未收到匹配回复；已结束连接，请重新扫描")
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "蓝牙已开启"
            if wantScan { beginScan() }
        case .unauthorized: status = "蓝牙权限未允许，请在系统设置中开启"
        case .poweredOff: status = "系统蓝牙已关闭"
        case .unsupported: status = "此设备不支持蓝牙"
        case .resetting: status = "系统蓝牙正在重置"
        default: status = "等待系统蓝牙状态"
        }
        if central.state != .poweredOn {
            scanDeadline?.cancel()
            isScanning = false
            resetLink()
            peripheral = nil
        }
        log(status)
    }

    func centralManager(_ central: CBCentralManager, didDiscover target: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? target.name ?? "FPGA-Instrument"
        peripherals[target.identifier] = target
        let device = Device(id: target.identifier, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect target: CBPeripheral) {
        guard target === peripheral else { return }
        status = "已连接 ESP，正在发现服务"
        log(status)
        target.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect target: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        resetLink()
        peripheral = nil
        status = "连接失败：\(error?.localizedDescription ?? "请重试")"
        log(status)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral target: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        resetLink()
        peripheral = nil
        status = error.map { "连接断开：\($0.localizedDescription)" } ?? "已断开，可重新扫描"
        performanceProtocolStatus = "连接已断开；演奏能力未确认"
        log(status)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            fail("未找到目标蓝牙服务")
            return
        }
        peripheral.discoverCharacteristics([rxID, txID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil else { fail("收发特征发现失败"); return }
        rx = service.characteristics?.first(where: { $0.uuid == rxID })
        tx = service.characteristics?.first(where: { $0.uuid == txID })
        guard let rx = rx, let tx = tx,
              (rx.properties.contains(.write) || rx.properties.contains(.writeWithoutResponse)),
              tx.properties.contains(.notify) else {
            fail("设备缺少可写入或可订阅的收发特征")
            return
        }
        status = "正在订阅回复通知"
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == txID else { return }
        guard error == nil, characteristic.isNotifying else { fail("通知订阅失败"); return }
        connectionDeadline?.cancel()
        isConnecting = false
        isReady = true
        performanceReady = false
        negotiatedCapabilities = nil
        capabilityReplyFormat = nil
        capabilityVersion = nil
        capabilityMask = nil
        capabilityStatus = nil
        performanceProtocolStatus = "BLE 通知已订阅；正在查询 FPGA 演奏能力"
        status = "BLE 已连接；查询 FPGA 演奏能力"
        log("通知订阅成功；发送 E1 00 查询演奏能力")
        sendCapabilityQuery()
    }

    func requestPerformanceCapability() {
        guard isReady else { return }
        capabilityDeadline?.cancel()
        capabilityQueryPending = false
        sendCapabilityQuery()
    }

    private func sendCapabilityQuery() {
        guard isReady, !capabilityQueryPending, let target = peripheral, let rx = rx else {
            return
        }
        guard !performanceWriteInFlight, performanceQueue.isEmpty else {
            performanceLastError = "演奏发送期间暂缓能力查询"
            return
        }
        let writeType: CBCharacteristicWriteType
        if rx.properties.contains(.write) {
            writeType = .withResponse
        } else if rx.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            performanceLastError = "RX 特征不可写，无法查询能力"
            return
        }
        let data = Data([0xE1, 0x00])
        guard data.count <= target.maximumWriteValueLength(for: writeType) else {
            performanceLastError = "能力查询包超过 MTU"
            return
        }
        capabilityQueryPending = true
        performanceReady = false
        negotiatedCapabilities = nil
        capabilityReplyFormat = nil
        capabilityVersion = nil
        capabilityMask = nil
        capabilityStatus = nil
        performanceProtocolStatus = "已发送 E1 00；等待 CAPS v2 或 FPGA_STATUS v1"
        status = "等待 FPGA 演奏能力回复"
        capabilityLog("能力查询 E1 00")
        target.writeValue(data, for: rx, type: writeType)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.capabilityQueryPending else { return }
            self.capabilityQueryPending = false
            self.performanceReady = false
            self.negotiatedCapabilities = nil
            self.performanceProtocolStatus = "能力查询超时；CAPS/FPGA_STATUS 未收到"
            self.performanceLastError = "能力查询超时"
            self.logThrottled("未收到 CAPS/FPGA_STATUS；硬件演奏不开放")
        }
        capabilityDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func handleCapabilityReply(_ text: String) {
        capabilityQueryPending = false
        capabilityDeadline?.cancel()
        capabilityDeadline = nil

        switch CapabilityReplyParser.parse(text) {
        case .success(let capability):
            capabilityVersion = capability.version
            capabilityMask = capability.mask
            capabilityStatus = capability.status
            capabilityReplyFormat = capability.format
            negotiatedCapabilities = capability
            performanceReady = capability.isReady
            performanceProtocolStatus = capability.statusText
            performanceLastError = capability.isReady ? "—" : capability.statusText
            if capability.isReady {
                self.status = capability.isV1 ? "FPGA v1 基础演奏就绪" : "FPGA v2 扩展演奏就绪"
            } else {
                self.status = "能力已回复，但演奏未开放"
            }
            logThrottled("演奏能力回复（\(capability.format.rawValue)）：\(text)")
        case .failure(let error):
            negotiatedCapabilities = nil
            performanceReady = false
            capabilityReplyFormat = nil
            capabilityVersion = nil
            capabilityMask = nil
            capabilityStatus = nil
            performanceProtocolStatus = "能力回复异常：\(error.message)"
            performanceLastError = error.message
            self.status = "能力回复异常，不开放硬件"
            logThrottled("演奏能力回复异常：\(text) · \(error.message)")
        }
    }

    func sendLinkLevelReleaseAll() {
        guard isReady, let target = peripheral, let rx = rx else { return }
        guard !performanceWriteInFlight, performanceQueue.isEmpty else {
            logThrottled("链路级释放延后：演奏写入仍在队列")
            return
        }
        guard rx.properties.contains(.write) else { return }
        let data = Data([0xE0, 0x05, 0x00, 0x00])
        guard data.count <= target.maximumWriteValueLength(for: .withResponse) else { return }
        target.writeValue(data, for: rx, type: .withResponse)
        performanceLastError = "能力失效，已发送链路级 BLE 释放"
        logThrottled("能力失效，发送链路级 BLE_RELEASE_ALL")
    }

    private func capabilityLog(_ text: String) {
        logThrottled(text)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == rxID else { return }
        if musicWriteInFlight {
            if let error {
                finishMusicWrite(.failure(error))
            } else {
                finishMusicWrite(.success(()))
            }
            return
        }
        if performanceWriteInFlight {
            performanceWriteInFlight = false
            let packet = performanceInFlightPacket
            let wasProtected = performanceInFlightGroupProtected
            performanceInFlightPacket = nil
            performanceInFlightGroupProtected = false
            if let error = error {
                performanceLastError = "演奏写入失败：\(error.localizedDescription)"
                if let packet {
                    _ = performanceQueue.enqueueFrontGroup(
                        PerformancePacketGroup(
                            packets: [packet],
                            label: "retry-\(packet.label)",
                            isProtected: wasProtected,
                            session: sessionGeneration
                        )
                    )
                }
                updateQueueMetrics()
                logThrottled("演奏写入失败；失败包已回队，组内后续包保持顺序")
            } else {
                performanceLastError = "—"
                logThrottled("演奏包写入确认（ATT 确认，不代表 FPGA 已执行）")
                updateQueueMetrics()
                drainPerformanceQueue()
            }
            return
        }
        if let error = error { fail("写入失败：\(error.localizedDescription)"); return }
        // An ATT write ACK proves delivery to ESP, not execution by FPGA.
        log("ESP 写入确认（不等于 FPGA 已回复）")
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        drainPerformanceQueue()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == txID else { return }
        guard error == nil, let data = characteristic.value else {
            log("回复读取失败")
            return
        }
        if data.first == 0xE2 {
            onMusicFrame?(data)
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            log("回复读取失败或不是文本编码")
            return
        }
        lastReply = text
        log("收到 \(text)")
        if capabilityQueryPending,
           (text.hasPrefix("CAPS;") || text.hasPrefix("FPGA_STATUS;")) {
            handleCapabilityReply(text)
            return
        }
        if capabilityQueryPending, text.hasPrefix("ERR:") {
            capabilityQueryPending = false
            capabilityDeadline?.cancel()
            capabilityDeadline = nil
            performanceReady = false
            negotiatedCapabilities = nil
            capabilityReplyFormat = nil
            performanceProtocolStatus = "能力查询失败：\(text)"
            performanceLastError = text
            status = "能力查询失败，不开放硬件"
            logThrottled("能力查询失败：\(text)")
            return
        }
        if text.hasPrefix("ERR:"), performanceReady,
           lastPerformanceSubmitUptime > 0,
           ProcessInfo.processInfo.systemUptime - lastPerformanceSubmitUptime < 2.0 {
            performanceLastError = text
            logThrottled("演奏错误: \(text)")
            return
        }
        guard let active = request else { return }
        let matches: Bool
        switch active.command {
        case "PING": matches = text == "PONG"
        case "FPGA_PING":
            let prefix = "FPGA_PONG seq="
            matches = text.hasPrefix(prefix) && UInt8(String(text.dropFirst(prefix.count))) != nil
        case "STATUS": matches = text.hasPrefix("STATUS;")
        default: matches = false
        }
        guard matches || text.hasPrefix("ERR:") else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - active.sent) * 1000
        roundTrip = String(format: "%.1f ms", elapsed)
        deadline?.cancel()
        request = nil
        isBusy = false
        if active.command == "FPGA_PING" { fpgaVerified = matches }
        log("\(active.command) 往返 \(roundTrip)\(matches ? "" : " · 设备报错")")
    }
}
