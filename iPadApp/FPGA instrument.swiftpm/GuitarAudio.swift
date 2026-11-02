import Foundation
import AVFoundation
import Combine

final class GuitarSoundEngine: ObservableObject {
    enum Status: Equatable {
        case unprepared
        case preparing
        case ready
        case unavailable(String)
    }

    @Published private(set) var status: Status = .unprepared

    private let engine = AVAudioEngine()
    private let pitches: [Int]
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var nextPlayerIndex: Int = 0
    private var graphReady: Bool = false
    private let voiceCount: Int = 12
    private let bufferDuration: TimeInterval = 1.30
    private var masterVolume: Float = 1.0

    init(pitches: [Int]) {
        self.pitches = Array(Set(pitches)).sorted()
    }

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
            return "本地音色就绪"
        case .unavailable:
            return "无声演示"
        }
    }

    var statusDetail: String {
        switch status {
        case .unprepared:
            return "进入电吉他练习前会准备本地演示音色"
        case .preparing:
            return "正在准备本地电吉他演示音色"
        case .ready:
            return "本地电吉他演示音色（非 FPGA 音色）"
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
        for midiNote in pitches {
            guard let buffer = makeBuffer(
                midiNote: midiNote,
                format: monoFormat,
                sampleRate: sampleRate
            ) else {
                status = .unavailable("电吉他缓冲创建失败，当前为无声演示")
                return
            }
            newBuffers[midiNote] = buffer
        }
        buffers = newBuffers

        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            player.volume = 0.82
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: monoFormat)
            players.append(player)
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

    func play(midiNote: Int, velocity: Int = 15) {
        guard isReady, let buffer = buffers[midiNote], !players.isEmpty else { return }
        guard ensureEngineRunning() else { return }

        let player = players[nextPlayerIndex]
        nextPlayerIndex += 1
        if nextPlayerIndex >= players.count {
            nextPlayerIndex = 0
        }

        player.stop()
        player.volume = 0.82 * Self.noteGain(velocity)
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func setMasterVolume(_ volume: Double) {
        masterVolume = Float(min(max(volume, 0), 1))
        engine.mainMixerNode.outputVolume = masterVolume
    }

    func stopAll() {
        for player in players {
            player.stop()
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

    private func makeBuffer(
        midiNote: Int,
        format: AVAudioFormat,
        sampleRate: Double
    ) -> AVAudioPCMBuffer? {
        let frequency: Double = 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
        let frameCountDouble: Double = sampleRate * bufferDuration
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
        let attack: Double = 0.004
        let decayRate: Double = 3.8
        let releaseStart: Double = bufferDuration - 0.08
        let totalFrames: Int = Int(frameCount)

        for frame in 0..<totalFrames {
            let time: Double = Double(frame) / sampleRate
            let phase: Double = twoPi * frequency * time
            let attackGain: Double = min(1.0, time / attack)
            let decay: Double = exp(-decayRate * time)
            var releaseGain: Double = 1.0
            if time > releaseStart {
                releaseGain = max(0.0, (bufferDuration - time) / 0.08)
            }

            let h1: Double = sin(phase)
            let h2: Double = 0.46 * sin(phase * 2.0)
            let h3: Double = 0.30 * sin(phase * 3.0)
            let h4: Double = 0.18 * sin(phase * 4.0)
            let h5: Double = 0.09 * sin(phase * 5.0)
            let rawWave: Double = h1 + h2 + h3 + h4 + h5
            let clippedWave: Double = tanh(rawWave * 1.18)
            let amplitude: Double = 0.14
            let value: Double = clippedWave * attackGain * decay * releaseGain * amplitude
            samples[frame] = Float(value)
        }

        return buffer
    }
}
