import Foundation
import SpriteKit

final class DrumKitPracticeSession: PracticeSession {
    let drumKitChart: DrumKitChart
    private var loadedAudio: DrumKitSoundEngine?

    var audio: DrumKitSoundEngine {
        if let loadedAudio {
            return loadedAudio
        }
        let createdAudio = DrumKitSoundEngine()
        loadedAudio = createdAudio
        return createdAudio
    }

    init() {
        let chart = DrumKitChart.builtIn
        self.drumKitChart = chart
        super.init(chart: chart.practiceChart)
    }

    func prepareAudio() {
        audio.prepare()
    }

    func suspendAudioIfLoaded() {
        loadedAudio?.suspend()
    }

    override func makeScene() -> SKScene {
        DrumGridScene(
            session: self,
            chart: drumKitChart,
            audio: audio
        )
    }
}
