import Foundation
import Combine

final class FreePlayAudio: ObservableObject {
    @Published private(set) var summary: String = "准备本地音色"
    @Published private(set) var isReady: Bool = false

    private let piano = PianoSoundEngine(extraMIDINotes: Array(48...87))
    private let guitar = GuitarSoundEngine(pitches: Array(40...76))
    private let drums = DrumKitSoundEngine()
    private var masterVolume: Double = 0.80
    private var didPrepare = false

    func prepare() {
        piano.prepare()
        guitar.prepare()
        drums.prepare()
        didPrepare = true

        let readyCount: Int = [piano.isReady, guitar.isReady, drums.isReady].filter { $0 }.count
        isReady = readyCount == 3
        switch readyCount {
        case 3:
            summary = "本地三乐器就绪 · 非 FPGA 音色"
        case 0:
            summary = "无声演示 · 本地音频不可用"
        default:
            summary = "本地演示 · \(readyCount)/3 音色就绪"
        }
        applyMasterVolume()
    }

    func setMasterVolume(_ volume: Double) {
        masterVolume = min(max(volume, 0), 1)
        applyMasterVolume()
    }

    func playPiano(midiNote: Int, velocity: Int) {
        let safe: Int = min(max(midiNote, 0), 127)
        piano.play(midiNote: safe, velocity: velocity)
    }

    func playString(stringIndex: Int, fret: Int, velocity: Int) {
        guard stringIndex >= 0, stringIndex < FPGAKeyMap.guitarStrings.count else { return }
        let string = FPGAKeyMap.guitarStrings[stringIndex]
        let safeFret: Int = min(max(fret, 0), 12)
        guitar.play(midiNote: string.openMIDINote + safeFret, velocity: velocity)
    }

    func playChord(_ chord: FPGAGuitarChord, velocity: Int) {
        for tone in chord.tones {
            guitar.play(midiNote: tone.midiNote, velocity: velocity)
        }
    }

    func playDrum(_ instrument: DrumKitInstrument, velocity: Int) {
        drums.play(instrument: instrument, velocity: velocity)
    }

    func stopAll() {
        piano.stopAll()
        guitar.stopAll()
        drums.stopAll()
    }

    func suspendAll() {
        piano.suspend()
        guitar.suspend()
        drums.suspend()
        isReady = false
        if didPrepare {
            summary = "本地音色已暂停"
        }
    }

    private func applyMasterVolume() {
        piano.setMasterVolume(masterVolume)
        guitar.setMasterVolume(masterVolume)
        drums.setMasterVolume(masterVolume)
    }
}