import Foundation

struct PerformanceWireEncoder {
    let capabilities: PerformanceCapabilities?

    init(capabilities: PerformanceCapabilities?) {
        self.capabilities = capabilities
    }

    var isV2: Bool { capabilities?.supportsExtendedEvents == true }

    func supports(_ control: PerformanceControl) -> Bool {
        capabilities?.supports(control) ?? false
    }

    func pianoNoteOn(key: Int, velocity: Int, octave: Int) -> PerformancePacketGroup? {
        guard let capabilities else { return nil }
        if capabilities.isV1 {
            guard (0..<16).contains(key), supports(.piano) else { return nil }
            return group(
                [packet(0x01, key, clampedVelocity(velocity))],
                label: "v1-piano-on-\(key)"
            )
        }
        guard supports(.piano), (0..<16).contains(key) else { return nil }
        var packets: [PerformanceQueuePacket] = []
        if supports(.pianoOctave) {
            packets.append(packet(0x30, min(max(octave, 0), 2), 0))
        }
        packets.append(packet(0x01, key, clampedVelocity(velocity)))
        return group(packets, label: "v2-piano-on-\(key)")
    }

    func pianoNoteOff(key: Int) -> PerformancePacketGroup? {
        guard let capabilities, supports(.piano), (0..<16).contains(key) else { return nil }
        return group(
            [packet(0x02, key, 0)],
            label: "piano-off-\(key)",
            isProtected: true
        )
    }

    func drum(key: Int, velocity: Int) -> PerformancePacketGroup? {
        guard let capabilities, supports(.drums), (0..<9).contains(key) else { return nil }
        return group(
            [packet(0x03, key, clampedVelocity(velocity))],
            label: "drum-\(key)"
        )
    }

    func guitarPluck(string: Int, velocity: Int, fret: Int, palmMuted: Bool) -> PerformancePacketGroup? {
        guard let capabilities, supports(.guitarPluck), (0..<6).contains(string) else { return nil }
        if capabilities.isV1 {
            return group(
                [packet(0x04, string, 0x0F)],
                label: "v1-guitar-\(string)"
            )
        }
        var packets: [PerformanceQueuePacket] = []
        if supports(.guitarFret) {
            packets.append(packet(0x21, min(max(fret, 0), 12), 0))
        }
        if supports(.guitarPalm) {
            packets.append(packet(0x22, palmMuted ? 1 : 0, 0))
        }
        packets.append(packet(0x20, string, clampedVelocity(velocity)))
        return group(packets, label: "v2-guitar-\(string)")
    }

    func chordSelect(_ chordID: Int) -> PerformancePacketGroup? {
        guard supports(.chords), (0..<4).contains(chordID) else { return nil }
        return parameter(0x23, chordID, label: "chord-select-\(chordID)")
    }

    func chord(chordID: Int, velocity: Int) -> PerformancePacketGroup? {
        guard let capabilities, supports(.chords), (0..<4).contains(chordID) else { return nil }
        return group(
            [
                packet(0x23, chordID, 0),
                packet(0x24, 0, clampedVelocity(velocity))
            ],
            label: "chord-\(chordID)"
        )
    }

    func chordRelease() -> PerformancePacketGroup? {
        guard supports(.chords) else { return nil }
        return group([packet(0x25, 0, 0)], label: "chord-cancel", isProtected: true)
    }

    func octave(_ value: Int) -> PerformancePacketGroup? {
        guard supports(.pianoOctave), (0..<3).contains(value) else { return nil }
        return parameter(0x30, value, label: "piano-oct-\(value)")
    }

    func fret(_ value: Int) -> PerformancePacketGroup? {
        guard supports(.guitarFret), (0...12).contains(value) else { return nil }
        return parameter(0x21, value, label: "guitar-fret-\(value)")
    }

    func palm(_ muted: Bool) -> PerformancePacketGroup? {
        guard supports(.guitarPalm) else { return nil }
        return parameter(0x22, muted ? 1 : 0, label: "guitar-palm-\(muted ? 1 : 0)")
    }

    func bend(_ state: PerformanceBend) -> PerformancePacketGroup? {
        guard supports(.bendVibrato) else { return nil }
        return group(
            [packet(0x26, state.rawValue, 0)],
            label: "bend-\(state.rawValue)",
            isProtected: state == .center
        )
    }

    func vibrato(_ enabled: Bool) -> PerformancePacketGroup? {
        guard supports(.bendVibrato) else { return nil }
        return parameter(0x27, enabled ? 1 : 0, label: "vibrato-\(enabled ? 1 : 0)")
    }

    func glide(_ enabled: Bool) -> PerformancePacketGroup? {
        guard supports(.glideSlide) else { return nil }
        return parameter(0x28, enabled ? 1 : 0, label: "glide-\(enabled ? 1 : 0)")
    }

    func slideStep(_ step: Int) -> PerformancePacketGroup? {
        guard supports(.glideSlide), PerformanceSlideTime.range.contains(step) else { return nil }
        return parameter(0x29, step, label: "slide-\(step)")
    }

    func overdrive(_ enabled: Bool) -> PerformancePacketGroup? {
        guard supports(.overdrive) else { return nil }
        return parameter(0x2A, enabled ? 1 : 0, label: "overdrive-\(enabled ? 1 : 0)")
    }

    func reverb(_ enabled: Bool) -> PerformancePacketGroup? {
        guard supports(.reverb) else { return nil }
        return parameter(0x2B, enabled ? 1 : 0, label: "reverb-\(enabled ? 1 : 0)")
    }

    func damping(_ enabled: Bool) -> PerformancePacketGroup? {
        guard supports(.dampingPedal) else { return nil }
        return parameter(0x31, enabled ? 1 : 0, label: "damping-\(enabled ? 1 : 0)")
    }

    func pedal(_ down: Bool) -> PerformancePacketGroup? {
        guard supports(.dampingPedal) else { return nil }
        var packets = [packet(0x32, down ? 1 : 0, 0)]
        if !down {
            packets.append(packet(0x33, 0, 0))
        }
        return group(
            packets,
            label: "pedal-\(down ? 1 : 0)",
            isProtected: !down
        )
    }

    func pedalRelease() -> PerformancePacketGroup? {
        guard supports(.dampingPedal) else { return nil }
        return group([packet(0x33, 0, 0)], label: "pedal-release", isProtected: true)
    }

    func releaseAll() -> PerformancePacketGroup? {
        guard let capabilities, supports(.releaseAll) else { return nil }
        return group([packet(0x05, 0, 0)], label: "release-all", isProtected: true, clearsPending: true)
    }

    func allStop() -> PerformancePacketGroup? {
        guard let capabilities, supports(.allOff) else { return nil }
        return group([packet(0x06, 0, 0)], label: "all-stop", isProtected: true, clearsPending: true)
    }

    func cleanupExpressionAndRelease() -> PerformancePacketGroup? {
        guard let capabilities else { return nil }
        if capabilities.isV1 {
            return releaseAll()
        }
        var packets: [PerformanceQueuePacket] = []
        if supports(.bendVibrato) {
            packets.append(packet(0x26, PerformanceBend.center.rawValue, 0))
            packets.append(packet(0x27, 0, 0))
        }
        if supports(.glideSlide) {
            packets.append(packet(0x28, 0, 0))
        }
        if supports(.dampingPedal) {
            packets.append(packet(0x32, 0, 0))
            packets.append(packet(0x33, 0, 0))
        }
        if supports(.chords) {
            packets.append(packet(0x25, 0, 0))
        }
        if supports(.releaseAll) {
            packets.append(packet(0x05, 0, 0))
        }
        guard !packets.isEmpty else { return nil }
        return group(packets, label: "cleanup-release", isProtected: true, clearsPending: true)
    }

    func restoreGroup(
        octave: Int,
        fret: Int,
        palmMuted: Bool,
        damping: Bool,
        pedalDown: Bool,
        bendState: PerformanceBend,
        vibrato: Bool,
        glide: Bool,
        slideStep: Int
    ) -> PerformancePacketGroup? {
        guard let capabilities else { return nil }
        if capabilities.isV1 {
            return nil
        }
        var packets: [PerformanceQueuePacket] = []
        if supports(.releaseAll) {
            packets.append(packet(0x05, 0, 0))
        }
        if supports(.pianoOctave) {
            packets.append(packet(0x30, min(max(octave, 0), 2), 0))
        }
        if supports(.guitarFret) {
            packets.append(packet(0x21, min(max(fret, 0), 12), 0))
        }
        if supports(.guitarPalm) {
            packets.append(packet(0x22, palmMuted ? 1 : 0, 0))
        }
        if supports(.dampingPedal) {
            packets.append(packet(0x31, damping ? 1 : 0, 0))
            packets.append(packet(0x32, pedalDown ? 1 : 0, 0))
            if !pedalDown {
                packets.append(packet(0x33, 0, 0))
            }
        }
        if supports(.bendVibrato) {
            packets.append(packet(0x26, bendState.rawValue, 0))
            packets.append(packet(0x27, vibrato ? 1 : 0, 0))
        }
        if supports(.glideSlide) {
            packets.append(packet(0x28, glide ? 1 : 0, 0))
            packets.append(packet(0x29, min(max(slideStep, 1), 15), 0))
        }
        guard !packets.isEmpty else { return nil }
        return group(packets, label: "restore-state", isProtected: true, clearsPending: true)
    }

    private func parameter(_ event: UInt8, _ key: Int, label: String) -> PerformancePacketGroup? {
        group(
            [packet(event, key, 0)],
            label: label,
            coalescingKey: "param-\(event)"
        )
    }

    private func packet(_ event: UInt8, _ key: Int, _ value: Int) -> PerformanceQueuePacket {
        PerformanceQueuePacket(
            data: Data([
                0xE0,
                event,
                UInt8(clamping: key),
                UInt8(clamping: value)
            ]),
            label: String(format: "E0-%02X-%02X-%02X", event, UInt8(clamping: key), UInt8(clamping: value))
        )
    }

    private func group(
        _ packets: [PerformanceQueuePacket],
        label: String,
        isProtected: Bool = false,
        coalescingKey: String? = nil,
        clearsPending: Bool = false
    ) -> PerformancePacketGroup {
        PerformancePacketGroup(
            packets: packets,
            label: label,
            isProtected: isProtected,
            coalescingKey: coalescingKey,
            clearsPending: clearsPending
        )
    }

    private func clampedVelocity(_ value: Int) -> Int {
        min(max(value, 1), 15)
    }
}

