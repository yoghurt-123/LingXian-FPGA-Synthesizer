import Foundation

struct PerformanceQueuePacket: Equatable {
    let data: Data
    let label: String
}

struct PerformancePacketGroup: Equatable {
    var packets: [PerformanceQueuePacket]
    let label: String
    let isProtected: Bool
    let coalescingKey: String?
    let session: Int
    let clearsPending: Bool

    init(
        packets: [PerformanceQueuePacket],
        label: String,
        isProtected: Bool = false,
        coalescingKey: String? = nil,
        session: Int = 0,
        clearsPending: Bool = false
    ) {
        self.packets = packets
        self.label = label
        self.isProtected = isProtected
        self.coalescingKey = coalescingKey
        self.session = session
        self.clearsPending = clearsPending
    }

    var packetCount: Int { packets.count }

    func withSession(_ session: Int) -> PerformancePacketGroup {
        PerformancePacketGroup(
            packets: packets,
            label: label,
            isProtected: isProtected,
            coalescingKey: coalescingKey,
            session: session,
            clearsPending: clearsPending
        )
    }
}

final class PerformanceCommandQueue {
    let limit: Int
    private(set) var groups: [PerformancePacketGroup] = []
    private(set) var droppedCount: Int = 0
    private(set) var coalescedCount: Int = 0
    private(set) var maxDepth: Int = 0
    private(set) var rejectedCount: Int = 0

    init(limit: Int = 16) {
        self.limit = max(1, limit)
    }

    var count: Int { groups.reduce(0) { $0 + $1.packetCount } }
    var groupCount: Int { groups.count }
    var isEmpty: Bool { groups.isEmpty }
    var packets: [PerformanceQueuePacket] { groups.flatMap(\.packets) }
    var frontGroupIsProtected: Bool { groups.first?.isProtected ?? false }

    @discardableResult
    func enqueue(_ packet: PerformanceQueuePacket) -> Bool {
        enqueueGroup(
            PerformancePacketGroup(
                packets: [packet],
                label: packet.label
            )
        )
    }

    @discardableResult
    func enqueueGroup(_ group: PerformancePacketGroup) -> Bool {
        guard !group.packets.isEmpty else { return false }
        guard group.packetCount <= limit else {
            rejectedCount += 1
            return false
        }

        if let key = group.coalescingKey,
           let last = groups.last,
           !last.isProtected,
           last.session == group.session,
           last.coalescingKey == key {
            groups[groups.count - 1] = group
            coalescedCount += 1
            maxDepth = max(maxDepth, count)
            return true
        }

        while count + group.packetCount > limit {
            guard let index = groups.firstIndex(where: { !$0.isProtected }) else {
                rejectedCount += 1
                return false
            }
            let removed = groups.remove(at: index)
            droppedCount += removed.packetCount
        }

        groups.append(group)
        maxDepth = max(maxDepth, count)
        return true
    }

    @discardableResult
    func enqueueFrontGroup(_ group: PerformancePacketGroup) -> Bool {
        guard !group.packets.isEmpty else { return false }
        guard group.packetCount <= limit else {
            rejectedCount += 1
            return false
        }
        while count + group.packetCount > limit {
            guard let index = groups.firstIndex(where: { !$0.isProtected }) else {
                rejectedCount += 1
                return false
            }
            let removed = groups.remove(at: index)
            droppedCount += removed.packetCount
        }
        groups.insert(group, at: 0)
        maxDepth = max(maxDepth, count)
        return true
    }

    func dequeuePacket() -> PerformanceQueuePacket? {
        guard !groups.isEmpty else { return nil }
        var group = groups[0]
        guard !group.packets.isEmpty else {
            groups.removeFirst()
            return dequeuePacket()
        }
        let packet = group.packets.removeFirst()
        if group.packets.isEmpty {
            groups.removeFirst()
        } else {
            groups[0] = group
        }
        return packet
    }

    func peekPacket() -> PerformanceQueuePacket? {
        groups.first?.packets.first
    }

    func clear(session: Int) {
        groups.removeAll { $0.session == session }
    }

    func clearAll() {
        groups.removeAll(keepingCapacity: true)
    }

    func removeAllNonProtected() {
        let removed = groups.filter { !$0.isProtected }
        guard !removed.isEmpty else { return }
        groups.removeAll { !$0.isProtected }
        droppedCount += removed.reduce(0) { $0 + $1.packetCount }
    }

    func resetMetrics() {
        droppedCount = 0
        coalescedCount = 0
        maxDepth = 0
        rejectedCount = 0
    }
}
