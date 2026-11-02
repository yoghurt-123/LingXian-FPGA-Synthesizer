import Foundation
import AVFoundation
import Combine

final class DrumKitSoundEngine: ObservableObject {
    enum Status: Equatable {
        case unprepared
        case preparing
        case ready
        case unavailable(String)
    }

    @Published private(set) var status: Status = .unprepared

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var voiceInstruments: [Int] = []
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var nextPlayerIndex: Int = 0
    private var graphReady: Bool = false
    private let voiceCount: Int = 12
    private var masterVolume: Float = 1.0

    var isReady: Bool {
        if case .ready = status {
            return true
        }
        return false
    }

    var statusTitle: String {
        switch status {
        case .unprepared:
            return "音色未准备"
        case .preparing:
            return "准备音色"
        case .ready:
            return "本地鼓组就绪"
        case .unavailable:
            return "无声演示"
        }
    }

    var statusDetail: String {
        switch status {
        case .unprepared:
            return "进入架子鼓练习前会准备本地鼓组演示音色"
        case .preparing:
            return "正在准备本地鼓组演示音色"
        case .ready:
            return "本地鼓组演示音色（非 FPGA 音色）"
        case .unavailable(let reason):
            return reason
        }
    }

    func prepare() {
        if isReady {
            _ = ensureEngineRunning()
            engine.mainMixerNode.outputVolume = masterVolume
            return
        }

        if graphReady {
            if ensureEngineRunning() {
                status = .ready
            }
            engine.mainMixerNode.outputVolume = masterVolume
            return
        }

        status = .preparing

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            status = .unavailable(
                "音频会话不可用（\(error.localizedDescription)），当前为无声演示"
            )
            return
        }

        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        var sampleRate: Double = outputFormat.sampleRate
        if sampleRate < 8000 {
            sampleRate = 44100
        }
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            status = .unavailable("无法创建音频格式，当前为无声演示")
            return
        }

        var newBuffers: [Int: AVAudioPCMBuffer] = [:]
        for instrument in DrumKitInstrument.allCases {
            let duration: TimeInterval = bufferDuration(for: instrument)
            guard let buffer = makeBuffer(
                for: instrument,
                duration: duration,
                format: monoFormat,
                sampleRate: sampleRate
            ) else {
                status = .unavailable("鼓组缓冲创建失败，当前为无声演示")
                return
            }
            newBuffers[instrument.rawValue] = buffer
        }
        buffers = newBuffers

        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            player.volume = 0.82
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: monoFormat)
            players.append(player)
            voiceInstruments.append(-1)
        }

        engine.mainMixerNode.outputVolume = masterVolume
        graphReady = true
        engine.prepare()
        do {
            try engine.start()
            status = .ready
        } catch {
            status = .unavailable(
                "音频引擎启动失败（\(error.localizedDescription)），当前为无声演示"
            )
        }
    }

    func play(instrument: DrumKitInstrument, velocity: Int = 15) {
        guard isReady, let buffer = buffers[instrument.rawValue], !players.isEmpty else {
            return
        }
        guard ensureEngineRunning() else { return }

        if instrument == .closedHat {
            chokeOpenHat()
        }

        let index: Int = nextPlayerIndex
        nextPlayerIndex += 1
        if nextPlayerIndex >= players.count {
            nextPlayerIndex = 0
        }

        let player = players[index]
        player.stop()
        player.volume = 0.82 * Self.noteGain(velocity)
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
        if voiceInstruments.indices.contains(index) {
            voiceInstruments[index] = instrument.rawValue
        }
    }

    func setMasterVolume(_ volume: Double) {
        masterVolume = Float(min(max(volume, 0), 1))
        engine.mainMixerNode.outputVolume = masterVolume
    }

    func chokeOpenHat() {
        for index in players.indices where voiceInstruments.indices.contains(index) {
            guard voiceInstruments[index] == DrumKitInstrument.openHat.rawValue else {
                continue
            }
            players[index].stop()
            voiceInstruments[index] = -1
        }
    }

    func stopAll() {
        for index in players.indices {
            players[index].stop()
            if voiceInstruments.indices.contains(index) {
                voiceInstruments[index] = -1
            }
        }
    }

    func suspend() {
        stopAll()
        if engine.isRunning {
            engine.pause()
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    @discardableResult
    private func ensureEngineRunning() -> Bool {
        if engine.isRunning {
            return true
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            try engine.start()
            return true
        } catch {
            status = .unavailable(
                "音频引擎无法恢复（\(error.localizedDescription)），当前为无声演示"
            )
            return false
        }
    }

    private static func noteGain(_ velocity: Int) -> Float {
        let safe: Float = Float(min(max(velocity, 0), 15)) / 15.0
        return 0.35 + 0.65 * safe
    }

    private func bufferDuration(for instrument: DrumKitInstrument) -> TimeInterval {
        switch instrument {
        case .kick: return 0.55
        case .snare: return 0.36
        case .closedHat: return 0.16
        case .openHat: return 0.90
        case .crash: return 1.15
        case .ride: return 0.75
        case .highTom, .midTom, .lowTom: return 0.58
        }
    }

    private func makeBuffer(
        for instrument: DrumKitInstrument,
        duration: TimeInterval,
        format: AVAudioFormat,
        sampleRate: Double
    ) -> AVAudioPCMBuffer? {
        let frameCountDouble: Double = sampleRate * duration
        let frameCount: AVAudioFrameCount = AVAudioFrameCount(frameCountDouble)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }

        let samples: UnsafeMutablePointer<Float> = channelData[0]
        let twoPi: Double = 2.0 * Double.pi
        let totalFrames: Int = Int(frameCount)
        var randomState: UInt32 = 0x12345678 &+ UInt32(instrument.rawValue) &* 0x9E3779B9

        for frame in 0..<totalFrames {
            let time: Double = Double(frame) / sampleRate
            randomState = randomState &* 1664525 &+ 1013904223
            let normalizedNoise: Double =
                Double(randomState) / Double(UInt32.max) * 2.0 - 1.0

            let sample: Double
            switch instrument {
            case .kick:
                let frequency: Double = 52.0 + 100.0 * exp(-time * 22.0)
                let body: Double = sin(twoPi * frequency * time) * exp(-time * 7.5)
                let click: Double = normalizedNoise * exp(-time * 55.0) * 0.18
                sample = body * 0.82 + click

            case .snare:
                let noise: Double = normalizedNoise * exp(-time * 15.0) * 0.55
                let body: Double = sin(twoPi * 185.0 * time) * exp(-time * 12.0) * 0.35
                sample = noise + body

            case .closedHat:
                let noise: Double = normalizedNoise * exp(-time * 58.0) * 0.45
                let metal: Double = sin(twoPi * 7600.0 * time) * exp(-time * 45.0) * 0.09
                sample = noise + metal

            case .openHat:
                let noise: Double = normalizedNoise * exp(-time * 8.5) * 0.40
                let metal: Double = sin(twoPi * 6900.0 * time) * exp(-time * 7.0) * 0.10
                sample = noise + metal

            case .crash:
                let noise: Double = normalizedNoise * exp(-time * 3.2) * 0.42
                let metal: Double =
                    (sin(twoPi * 3500.0 * time)
                    + 0.6 * sin(twoPi * 5200.0 * time)
                    + 0.35 * sin(twoPi * 7400.0 * time))
                    * exp(-time * 2.8) * 0.07
                sample = noise + metal

            case .ride:
                let noise: Double = normalizedNoise * exp(-time * 5.5) * 0.24
                let metal: Double =
                    (sin(twoPi * 2800.0 * time)
                    + 0.5 * sin(twoPi * 4300.0 * time))
                    * exp(-time * 4.5) * 0.10
                sample = noise + metal

            case .highTom:
                let frequency: Double = 210.0 + 70.0 * exp(-time * 12.0)
                sample = sin(twoPi * frequency * time) * exp(-time * 6.5) * 0.55

            case .midTom:
                let frequency: Double = 150.0 + 50.0 * exp(-time * 11.0)
                sample = sin(twoPi * frequency * time) * exp(-time * 6.0) * 0.55

            case .lowTom:
                let frequency: Double = 96.0 + 36.0 * exp(-time * 10.0)
                sample = sin(twoPi * frequency * time) * exp(-time * 5.5) * 0.58
            }

            let releaseWindow: Double = 0.06
            var releaseGain: Double = 1.0
            if time > duration - releaseWindow {
                releaseGain = max(0.0, (duration - time) / releaseWindow)
            }
            let finalSample: Double = tanh(sample * 1.1) * releaseGain
            samples[frame] = Float(finalSample)
        }

        return buffer
    }
}
