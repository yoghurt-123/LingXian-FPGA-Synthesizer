import Foundation
import SwiftUI

struct PerformanceSimTest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let passed: Bool
}

enum PerformanceSimulator {
    static func run() -> [PerformanceSimTest] {
        [
            v1CapabilityTest(),
            v2CapabilityTest(),
            invalidCapabilityTest(),
            capabilityBitGatingTest(),
            v1EncodingTest(),
            v2TriggerOrderTest(),
            parameterPositionTest(),
            queueAtomicGroupTest(),
            queueCoalescingBarrierTest(),
            protectedQueueTest(),
            restoreStateTest(),
            cleanupAndDisconnectTest(),
            releaseAndCancelTest(),
            drumMappingTest(),
            gameCapabilityTest(),
            pianoHoldTest(),
            speedClockTest()
        ] + MusicHallSimulator.run()
    }

    private static func v1CapabilityTest() -> PerformanceSimTest {
        let parsed = try? CapabilityReplyParser.parse("FPGA_STATUS;1;FFFF;0").get()
        let passed = parsed?.isV1 == true
            && parsed?.supports(.piano) == true
            && parsed?.supports(.guitarPluck) == true
            && parsed?.supports(.guitarFret) == false
            && parsed?.supports(.chords) == false
            && parsed?.isReady == true
        return PerformanceSimTest(
            title: "旧版 FPGA_STATUS v1",
            detail: passed ? "识别 v1 基础，不把 v1 掩码当作 v2 表情" : "旧版回复解析或能力选择错误",
            passed: passed
        )
    }

    private static func v2CapabilityTest() -> PerformanceSimTest {
        let parsed = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let passed = parsed?.isV2 == true
            && parsed?.mask == 0xFFFF
            && parsed?.supports(.piano) == true
            && parsed?.supports(.guitarFret) == true
            && parsed?.supports(.chords) == true
            && parsed?.supports(.dampingPedal) == true
            && parsed?.isReady == true
        return PerformanceSimTest(
            title: "新版 CAPS v2",
            detail: passed ? "识别 CAPS;2，按 32 位掩码开放扩展" : "CAPS v2 解析或能力位错误",
            passed: passed
        )
    }

    private static func invalidCapabilityTest() -> PerformanceSimTest {
        let overflow = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;1").get()
        let unknownVersion = CapabilityReplyParser.parse("CAPS;3;0000FFFF;0")
        let mismatch = CapabilityReplyParser.parse("CAPS;1;0000FFFF;0")
        let reserved = CapabilityReplyParser.parse("CAPS;2;0000FFFF;2")
        let zeroMask = try? CapabilityReplyParser.parse("CAPS;2;00000000;0").get()
        let passed = overflow?.isReady == false
            && overflow?.statusOverflow == true
            && (try? unknownVersion.get()) == nil
            && (try? mismatch.get()) == nil
            && (try? reserved.get()) == nil
            && zeroMask?.isReady == false
        return PerformanceSimTest(
            title: "能力异常与版本校验",
            detail: passed ? "未知版本/字段/结果位/零 mask 均不开放" : "异常能力没有明确拒绝",
            passed: passed
        )
    }

    private static func capabilityBitGatingTest() -> PerformanceSimTest {
        let parsed = try? CapabilityReplyParser.parse("CAPS;2;00000005;0").get()
        let passed = parsed?.isReady == true
            && parsed?.supports(.piano) == true
            && parsed?.supports(.guitarPluck) == true
            && parsed?.supports(.drums) == false
            && parsed?.supports(.guitarFret) == false
            && parsed?.supports(.chords) == false
        return PerformanceSimTest(
            title: "v2 能力位逐项开放",
            detail: passed ? "mask=0x00000005 只开放钢琴/吉他拨弦" : "未按实际 32 位掩码限制控件",
            passed: passed
        )
    }

    private static func v1EncodingTest() -> PerformanceSimTest {
        let caps = try? CapabilityReplyParser.parse("FPGA_STATUS;1;FFFF;0").get()
        let encoder = PerformanceWireEncoder(capabilities: caps)
        let piano = encoder.pianoNoteOn(key: 0, velocity: 15, octave: 2)
        let drum = encoder.drum(key: 4, velocity: 11)
        let guitar = encoder.guitarPluck(string: 2, velocity: 12, fret: 7, palmMuted: true)
        let release = encoder.releaseAll()
        let stop = encoder.allStop()
        let passed = piano?.packets.map(\.data) == [Data([0xE0, 0x01, 0x00, 0x0F])]
            && drum?.packets.map(\.data) == [Data([0xE0, 0x03, 0x04, 0x0B])]
            && guitar?.packets.map(\.data) == [Data([0xE0, 0x04, 0x02, 0x0F])]
            && release?.packets.map(\.data) == [Data([0xE0, 0x05, 0x00, 0x00])]
            && stop?.packets.map(\.data) == [Data([0xE0, 0x06, 0x00, 0x00])]
            && encoder.chord(chordID: 0, velocity: 15) == nil
        return PerformanceSimTest(
            title: "v1 基础事件编码",
            detail: passed ? "钢琴/九鼓/吉他 0x04/释放/全局停止保持兼容" : "v1 字节或能力门禁错误",
            passed: passed
        )
    }

    private static func v2TriggerOrderTest() -> PerformanceSimTest {
        let caps = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let encoder = PerformanceWireEncoder(capabilities: caps)
        let guitar = encoder.guitarPluck(string: 0, velocity: 12, fret: 3, palmMuted: true)
        let chord = encoder.chord(chordID: 0, velocity: 15)
        let piano = encoder.pianoNoteOn(key: 4, velocity: 9, octave: 2)
        let guitarData = guitar?.packets.map(\.data) ?? []
        let chordData = chord?.packets.map(\.data) ?? []
        let pianoData = piano?.packets.map(\.data) ?? []
        let passed = guitarData == [
            Data([0xE0, 0x21, 0x03, 0x00]),
            Data([0xE0, 0x22, 0x01, 0x00]),
            Data([0xE0, 0x20, 0x00, 0x0C])
        ] && chordData == [
            Data([0xE0, 0x23, 0x00, 0x00]),
            Data([0xE0, 0x24, 0x00, 0x0F])
        ] && pianoData == [
            Data([0xE0, 0x30, 0x02, 0x00]),
            Data([0xE0, 0x01, 0x04, 0x09])
        ]
        return PerformanceSimTest(
            title: "参数先于触发",
            detail: passed ? "品位/掌根→拨弦、选和弦→触发、八度→钢琴按下顺序正确" : "依赖序列顺序或 KEY/VALUE 位置错误",
            passed: passed
        )
    }

    private static func parameterPositionTest() -> PerformanceSimTest {
        let caps = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let encoder = PerformanceWireEncoder(capabilities: caps)
        let groups = [
            encoder.fret(12),
            encoder.palm(true),
            encoder.octave(2),
            encoder.bend(.left),
            encoder.vibrato(true),
            encoder.glide(true),
            encoder.slideStep(10),
            encoder.overdrive(true),
            encoder.reverb(false),
            encoder.damping(false)
        ]
        let allValueZero = groups.allSatisfy { group in
            group?.packets.allSatisfy { $0.data[3] == 0x00 } == true
        }
        let fret = encoder.fret(12)?.packets.first?.data == Data([0xE0, 0x21, 0x0C, 0x00])
        let bend = encoder.bend(.left)?.packets.first?.data == Data([0xE0, 0x26, 0x01, 0x00])
        let slide = encoder.slideStep(10)?.packets.first?.data == Data([0xE0, 0x29, 0x0A, 0x00])
        let pedalOff = encoder.pedal(false)?.packets.map(\.data) == [
            Data([0xE0, 0x32, 0x00, 0x00]),
            Data([0xE0, 0x33, 0x00, 0x00])
        ]
        let passed = allValueZero && fret && bend && slide && pedalOff
        return PerformanceSimTest(
            title: "参数 KEY 位与 VALUE=0",
            detail: passed ? "品位/弯音/滑时/踏板目标均在 KEY，VALUE 固定 0" : "参数被写进 VALUE 或释放序列错误",
            passed: passed
        )
    }

    private static func queueAtomicGroupTest() -> PerformanceSimTest {
        let queue = PerformanceCommandQueue(limit: 4)
        let first = makeGroup("g1", count: 2, session: 1)
        let second = makeGroup("g2", count: 2, session: 1)
        let third = makeGroup("g3", count: 3, session: 1)
        _ = queue.enqueueGroup(first)
        _ = queue.enqueueGroup(second)
        let accepted = queue.enqueueGroup(third)
        let passed = accepted
            && queue.groupCount == 1
            && queue.count == 3
            && queue.groups.first?.label == "g3"
            && !queue.groups.contains { $0.label == "g1" || $0.label == "g2" }
        return PerformanceSimTest(
            title: "队列满时整组原子",
            detail: passed ? "只丢完整旧组，不留下无前置参数的孤立触发" : "容量不足时拆散了依赖组",
            passed: passed
        )
    }

    private static func queueCoalescingBarrierTest() -> PerformanceSimTest {
        let queue = PerformanceCommandQueue(limit: 16)
        let fret3 = PerformancePacketGroup(
            packets: [PerformanceQueuePacket(data: Data([0xE0, 0x21, 0x03, 0x00]), label: "fret3")],
            label: "fret3",
            coalescingKey: "param-0x21",
            session: 1
        )
        let fret4 = PerformancePacketGroup(
            packets: [PerformanceQueuePacket(data: Data([0xE0, 0x21, 0x04, 0x00]), label: "fret4")],
            label: "fret4",
            coalescingKey: "param-0x21",
            session: 1
        )
        let trigger = makeGroup("pluck", count: 2, session: 1)
        _ = queue.enqueueGroup(fret3)
        _ = queue.enqueueGroup(fret4)
        let afterAdjacent = queue.count
        _ = queue.enqueueGroup(trigger)
        _ = queue.enqueueGroup(fret3)
        let passed = afterAdjacent == 1
            && queue.groupCount == 3
            && queue.coalescedCount == 1
            && queue.packets.filter { $0.data.starts(with: Data([0xE0, 0x21])) }.count == 2
        return PerformanceSimTest(
            title: "参数合并不跨触发",
            detail: passed ? "相邻同参数可合并，但不会替换触发前的旧参数" : "参数合并穿过了触发组",
            passed: passed
        )
    }

    private static func protectedQueueTest() -> PerformanceSimTest {
        let queue = PerformanceCommandQueue(limit: 2)
        _ = queue.enqueueGroup(
            PerformancePacketGroup(
                packets: [PerformanceQueuePacket(data: Data([0xE0, 0x02, 0x00, 0x00]), label: "off")],
                label: "off",
                isProtected: true,
                session: 1
            )
        )
        _ = queue.enqueueGroup(makeGroup("normal", count: 1, session: 1))
        let trigger = makeGroup("trigger", count: 2, session: 1)
        let accepted = queue.enqueueGroup(trigger)
        let passed = !accepted
            && queue.groupCount == 1
            && queue.groups.contains { $0.label == "off" }
            && queue.rejectedCount == 1
        return PerformanceSimTest(
            title: "保护组不静默丢失",
            detail: passed ? "保护 note-off 保留；整组触发因容量不足被拒绝" : "保护组或整组原子性错误",
            passed: passed
        )
    }

    private static func restoreStateTest() -> PerformanceSimTest {
        let caps = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let encoder = PerformanceWireEncoder(capabilities: caps)
        let group = encoder.restoreGroup(
            octave: 2,
            fret: 4,
            palmMuted: true,
            damping: false,
            pedalDown: false,
            bendState: .center,
            vibrato: false,
            glide: false,
            slideStep: 4
        )
        let events = group?.packets.map { $0.data[1] } ?? []
        let passed = events.contains(0x30)
            && events.contains(0x21)
            && events.contains(0x22)
            && events.contains(0x31)
            && events.contains(0x32)
            && events.contains(0x33)
            && events.contains(0x26)
            && !events.contains(0x2A)
            && !events.contains(0x2B)
        return PerformanceSimTest(
            title: "重进页面恢复状态",
            detail: passed ? "恢复八度/品位/掌根/阻尼/踏板；不重发共享过载/混响" : "恢复状态覆盖了共享 FX 或遗漏依赖状态",
            passed: passed
        )
    }

    private static func cleanupAndDisconnectTest() -> PerformanceSimTest {
        let caps = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let encoder = PerformanceWireEncoder(capabilities: caps)
        let cleanup = encoder.cleanupExpressionAndRelease()
        let events = cleanup?.packets.map { $0.data[1] } ?? []
        var ledger = PerformanceSessionLedger()
        _ = ledger.hold(token: 1, instrument: .piano, key: 2)
        _ = ledger.hold(token: 2, instrument: .piano, key: 3)
        let released = ledger.clearAfterDisconnect()
        let passed = events.contains(0x26)
            && events.contains(0x27)
            && events.contains(0x28)
            && events.contains(0x32)
            && events.contains(0x33)
            && events.contains(0x05)
            && released.count == 2
            && ledger.count == 0
        return PerformanceSimTest(
            title: "离开/断线清理",
            detail: passed ? "弯音回中、颤音/滑音关、踏板释放、BLE 释放；断线账本清空" : "清理组或断线清理不完整",
            passed: passed
        )
    }

    private static func releaseAndCancelTest() -> PerformanceSimTest {
        var ledger = PerformanceSessionLedger()
        _ = ledger.hold(token: 1, instrument: .piano, key: 0)
        _ = ledger.hold(token: 2, instrument: .piano, key: 1)
        let slide = ledger.release(token: 1, reason: .slideOut)
        let cancel = ledger.release(token: 2, reason: .cancel)
        let passed = slide?.reason == .slideOut
            && cancel?.reason == .cancel
            && ledger.count == 0
        return PerformanceSimTest(
            title: "松手/滑出/取消",
            detail: passed ? "触摸取消与滑出原因保留，不伪造持续和弦" : "释放原因或账本错误",
            passed: passed
        )
    }

    private static func drumMappingTest() -> PerformanceSimTest {
        let expected: [(DrumKitInstrument, Int)] = [
            (.kick, 0),
            (.snare, 1),
            (.closedHat, 2),
            (.openHat, 3),
            (.ride, 4),
            (.crash, 5),
            (.highTom, 6),
            (.lowTom, 7),
            (.midTom, 8)
        ]
        let passed = expected.allSatisfy { $0.0.bleProtocolKey == $0.1 }
        return PerformanceSimTest(
            title: "九鼓 UI → BLE 编号",
            detail: passed ? "Ride=4、Crash=5、LowTom=7、MidTom=8" : "鼓映射与协议不一致",
            passed: passed
        )
    }

    private static func pianoHoldTest() -> PerformanceSimTest {
        let chart = PracticeChart(
            title: "hold-test",
            bpm: 60,
            countdownDuration: 0,
            previewDuration: 2,
            perfectWindow: 0.10,
            goodWindow: 0.20,
            laneCount: 1,
            notes: [
                PracticeNote(id: 0, lane: 0, targetTime: 1, duration: 0.5)
            ]
        )

        let complete = PracticeSession(chart: chart)
        complete.start()
        complete.advance(to: 10)
        complete.advance(to: 11)
        _ = complete.registerHit(lane: 0, at: 1)
        let activeAfterHead = complete.isHoldActive(noteID: 0)
        complete.registerLaneRelease(lane: 0, at: 1.5)
        let completed = activeAfterHead
            && !complete.isHoldActive(noteID: 0)
            && complete.resolvedCount == 1
            && complete.stats.combo == 1
            && complete.stats.score > 100

        let early = PracticeSession(chart: chart)
        early.start()
        early.advance(to: 10)
        early.advance(to: 11)
        _ = early.registerHit(lane: 0, at: 1)
        early.registerLaneRelease(lane: 0, at: 1.1)
        let earlyBreak = early.resolvedCount == 1 && early.stats.combo == 0

        let late = PracticeSession(chart: chart)
        late.start()
        late.advance(to: 10)
        late.advance(to: 11)
        _ = late.registerHit(lane: 0, at: 1)
        late.advance(to: 12)
        let lateBreak = late.resolvedCount == 1
            && late.stats.combo == 0
            && !late.isHoldActive(noteID: 0)

        let passed = completed && earlyBreak && lateBreak
        return PerformanceSimTest(
            title: "钢琴长按状态机",
            detail: passed ? "长按完成加分；提前松手/超时断连并清理持有" : "长按持有、释放或超时状态错误",
            passed: passed
        )
    }

    private static func speedClockTest() -> PerformanceSimTest {
        let chart = PracticeChart(
            title: "speed-test",
            bpm: 60,
            countdownDuration: 0,
            previewDuration: 2,
            perfectWindow: 0.10,
            goodWindow: 0.20,
            laneCount: 1,
            notes: [PracticeNote(id: 0, lane: 0, targetTime: 10)]
        )
        let session = PracticeSession(chart: chart)
        session.speed = 0.5
        session.start()
        session.advance(to: 10)
        session.advance(to: 12)
        let passed = abs(session.practiceTime - 1.0) < 0.0001
        return PerformanceSimTest(
            title: "慢速统一时钟",
            detail: passed ? "0.5× 下 2 秒真实时间推进 1 秒谱面/判定/动画时钟" : "速度系数没有统一作用于游戏时钟",
            passed: passed
        )
    }

    private static func gameCapabilityTest() -> PerformanceSimTest {
        let v1 = try? CapabilityReplyParser.parse("FPGA_STATUS;1;FFFF;0").get()
        let v2 = try? CapabilityReplyParser.parse("CAPS;2;0000FFFF;0").get()
        let v1Piano = v1.map { PracticeGameKind.piano.isPlayable(with: $0) } ?? false
        let v1Drums = v1.map { PracticeGameKind.drums.isPlayable(with: $0) } ?? false
        let v1Guitar = v1.map { PracticeGameKind.guitar.isPlayable(with: $0) } ?? true
        let v2All = v2.map {
            PracticeGameKind.piano.isPlayable(with: $0)
                && PracticeGameKind.drums.isPlayable(with: $0)
                && PracticeGameKind.guitar.isPlayable(with: $0)
        } ?? false
        let passed = v1Piano && v1Drums && !v1Guitar && v2All
        return PerformanceSimTest(
            title: "音游能力门槛",
            detail: passed ? "v1 钢琴/九鼓可用，吉他音游需 v2 品位/和弦；v2 三音游可用" : "音游能力门槛或 v1 吉他回退判断错误",
            passed: passed
        )
    }

    private static func makeGroup(_ label: String, count: Int, session: Int) -> PerformancePacketGroup {
        let packets = (0..<count).map { index in
            PerformanceQueuePacket(
                data: Data([0xE0, UInt8(index), 0x00, 0x00]),
                label: "\(label)-\(index)"
            )
        }
        return PerformancePacketGroup(packets: packets, label: label, session: session)
    }
}

struct PerformanceSimulatorPanel: View {
    @State private var results: [PerformanceSimTest] = []
    @State private var hasRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("演奏协议模拟测试").font(.headline)
                    Text("源码逻辑测试：能力解析、v1/v2 编码、依赖顺序、队列原子性、恢复和清理；不代表 iPad 已运行。")
                        .font(.caption)
                        .foregroundStyle(PixelPalette.muted)
                }
                Spacer()
                Button("运行模拟") {
                    results = PerformanceSimulator.run()
                    hasRun = true
                }
                .buttonStyle(.borderedProminent)
            }

            if hasRun {
                ForEach(results) { result in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.passed ? PixelPalette.good : PixelPalette.miss)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title).font(.system(size: 12, weight: .semibold, design: .serif))
                            Text(result.detail).font(.caption).foregroundStyle(PixelPalette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                Text("模拟通过 \(results.filter { $0.passed }.count)/\(results.count)")
                    .font(.caption.bold())
                    .foregroundStyle(results.allSatisfy { $0.passed } ? PixelPalette.good : PixelPalette.miss)
            }
        }
        .padding(14)
        .background(PixelPalette.card)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 2))
    }
}
