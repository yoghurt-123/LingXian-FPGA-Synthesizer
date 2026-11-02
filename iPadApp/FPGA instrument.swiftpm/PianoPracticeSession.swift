import Foundation
import SpriteKit

final class PianoPracticeSession: PracticeSession {
    private var loadedAudio: PianoSoundEngine?

    var audio: PianoSoundEngine {
        if let loadedAudio {
            return loadedAudio
        }
        let createdAudio = PianoSoundEngine()
        loadedAudio = createdAudio
        return createdAudio
    }

    init() {
        super.init(chart: .piano)
    }

    func prepareAudio() {
        audio.prepare()
    }

    func suspendAudioIfLoaded() {
        loadedAudio?.suspend()
    }

    override func makeScene() -> SKScene {
        PianoScene(session: self, audio: audio)
    }
}
