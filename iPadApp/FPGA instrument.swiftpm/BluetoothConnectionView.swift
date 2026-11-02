import SwiftUI

struct BluetoothConnectionView: View {
    @ObservedObject var bluetooth: InstrumentBluetooth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("蓝牙诊断与演奏传输")
                    .font(.title2.bold())
                Text(bluetooth.shortStatus).font(.headline)
                Text("ESP v0.4 与 FPGA expression candidate 提供协议 v2；连接通知成功后自动发送 E1 00。新 App 同时识别旧版 FPGA_STATUS v1 和新版 CAPS v2；只有能力就绪后才开放 FPGA 音箱。PONG/FPGA_PONG 不会开放演奏。")
                    .foregroundStyle(PixelPalette.muted)
                connectionControls
                deviceList
                diagnosticPanel
                performancePanel
                PerformanceSimulatorPanel()
                logPanel
            }
            .padding(22)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var connectionControls: some View {
        HStack(spacing: 16) {
            Button(bluetooth.isScanning ? "重新扫描" : "扫描设备") { bluetooth.scan() }
                .disabled(bluetooth.isReady || bluetooth.isConnecting)
            Button("停止扫描") { bluetooth.stopScan() }.disabled(!bluetooth.isScanning)
            Button("断开连接") { bluetooth.disconnect() }
            Button("重置蓝牙会话") { bluetooth.resetConnection() }
        }
        .buttonStyle(PixelOutlineButtonStyle(fontSize: 11, horizontalPadding: 12, verticalPadding: 7))
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bluetooth.devices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name).bold()
                        Text("信号 \(device.rssi) dBm").font(.caption)
                    }
                    Spacer()
                    Button("连接") { bluetooth.connect(device.id) }
                        .buttonStyle(PixelFilledButtonStyle(fontSize: 11, horizontalPadding: 12, verticalPadding: 7))
                        .disabled(bluetooth.isReady || bluetooth.isConnecting)
                }
                .padding(12)
                .background(PixelPalette.secondary)
            }
        }
    }

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("链路诊断").font(.headline)
            HStack(spacing: 16) {
                Button("测试 ESP") { bluetooth.sendTest("PING") }
                Button("测试 FPGA") { bluetooth.sendTest("FPGA_PING") }
                Button("查询状态") { bluetooth.sendTest("STATUS") }
            }
            .buttonStyle(PixelOutlineButtonStyle(fontSize: 11, horizontalPadding: 12, verticalPadding: 7))
            .disabled(!bluetooth.isReady || bluetooth.isBusy)
            Text("最近回复：\(bluetooth.lastReply)")
                .font(.system(.body, design: .serif))
                .textSelection(.enabled)
            Text("往返耗时：\(bluetooth.roundTrip)").font(.title3.bold())
            Text(bluetooth.fpgaVerified ? "FPGA 串口回显通过：只证明链路，不代表演奏协议或音源就绪。" : "FPGA 尚未通过本次连接的回显测试。")
                .font(.caption)
            Text("一次只发一条诊断请求；3 秒无匹配回复会断开。诊断与演奏写入互斥，避免 ACK 串扰。")
                .font(.caption).foregroundStyle(PixelPalette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelPalette.card)
        .overlay(PixelPanelShape(cut: 10).stroke(PixelPalette.line, lineWidth: 0.9))
    }

    private var performancePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("演奏协议").font(.headline)
                Text(bluetooth.capabilityReplyFormat?.rawValue ?? "未协商")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PixelPalette.secondary)
                Spacer()
                Button("重新查询能力") { bluetooth.requestPerformanceCapability() }
                    .buttonStyle(PixelOutlineButtonStyle(fontSize: 11, horizontalPadding: 12, verticalPadding: 7))
                    .disabled(!bluetooth.isReady)
            }
            Text(bluetooth.performanceProtocolStatus)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(bluetooth.performanceReady ? PixelPalette.good : PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Text("通知：\(bluetooth.isReady ? "已订阅" : "未订阅")")
                Text("包队列：\(bluetooth.performanceQueueDepth)/16")
                Text("组：\(bluetooth.performanceGroupDepth)")
                Text("丢弃包：\(bluetooth.performanceDropped)")
                Text("拒绝组：\(bluetooth.performanceRejected)")
            }
            .font(.caption)
            HStack(spacing: 18) {
                Text("能力版本：\(bluetooth.capabilityVersion.map { String($0) } ?? "—")")
                Text("掩码：\(bluetooth.capabilityMask.map { String(format: "0x%08X", $0) } ?? "—")")
                Text("状态：\(bluetooth.capabilityStatus.map { String($0) } ?? "—")")
            }
            .font(.caption)
            if let capabilities = bluetooth.negotiatedCapabilities {
                Text("已声明：" + capabilities.supportedControls.map(\.title).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(PixelPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("最近错误：\(bluetooth.performanceLastError)")
                .font(.caption)
                .foregroundStyle(PixelPalette.muted)
            Text("v1 只开放旧基础事件；v2 按实际 32 位掩码逐项开放控件。CAPS 不回报效果当前值，所以过载/混响只显示 App 目标，不显示为已确认。")
                .font(.caption)
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelPalette.card)
        .overlay(PixelPanelShape(cut: 10).stroke(PixelPalette.line, lineWidth: 0.9))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("通信记录（最新在上）").font(.headline)
                Spacer()
                Button("清空") { bluetooth.clearLogs() }
                    .buttonStyle(PixelOutlineButtonStyle(fontSize: 10))
            }
            ForEach(Array(bluetooth.logs.reversed())) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(PixelPalette.muted)
                    Text(entry.text).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12, design: .serif))
            }
        }
        .textSelection(.enabled)
    }
}
