import Foundation
import Combine
import SpriteKit

final class GuitarPracticeSession: PracticeSession {
    let guitarChart: GuitarChart
    private var loadedAudio: GuitarSoundEngine?

    @Published private(set) var selectedFret: Int = 0
    @Published private(set) var selectedChordID: Int? = nil
    @Published private(set) var leftFeedback: String = "先选左手，再拨弦"

    var selectedLeft: GuitarLeftRequirement {
        if let id = selectedChordID {
            return .chord(id)
        }
        return .fret(selectedFret)
    }

    var audio: GuitarSoundEngine {
        if let loadedAudio {
            return loadedAudio
        }
        let createdAudio = GuitarSoundEngine(pitches: guitarChart.preparedMIDINotes)
        loadedAudio = createdAudio
        return createdAudio
    }

    init() {
        let chart = GuitarChart.builtIn
        self.guitarChart = chart
        super.init(chart: chart.practiceChart)
    }

    func prepareAudio() {
        audio.prepare()
    }

    func suspendAudioIfLoaded() {
        loadedAudio?.suspend()
    }

    override func start() {
        super.start()
        selectedFret = 0
        selectedChordID = nil
        leftFeedback = "先选左手，再拨弦"
        performanceController?.guitarSelectFret(0)
    }

    func selectFret(_ fret: Int) {
        selectedFret = min(max(fret, 0), 12)
        selectedChordID = nil
        leftFeedback = "左手：\(selectedFret)品"
        performanceController?.guitarSelectFret(selectedFret)
    }

    func selectChord(_ chordID: Int) {
        guard FPGAKeyMap.guitarChords.contains(where: { $0.id == chordID }) else { return }
        selectedChordID = chordID
        let name = FPGAKeyMap.guitarChords.first { $0.id == chordID }?.name ?? "和弦"
        leftFeedback = "左手：\(name) 和弦"
        performanceController?.guitarSelectChord(chordID)
    }

    func upcomingTarget(at time: TimeInterval, within preview: TimeInterval, lane: Int? = nil) -> GuitarNote? {
        var best: GuitarNote?
        for note in guitarChart.notes where !isResolved(noteID: note.id) {
            if let lane, note.lane != lane { continue }
            guard note.targetTime >= time - guitarChart.practiceChart.goodWindow else { continue }
            guard note.targetTime <= time + preview else { continue }
            if let current = best {
                if note.targetTime < current.targetTime {
                    best = note
                }
            } else {
                best = note
            }
        }
        return best
    }

    func isLeftMatched(for note: GuitarNote) -> Bool {
        switch note.left {
        case .fret(let fret):
            return selectedChordID == nil && selectedFret == fret
        case .chord(let chordID):
            return selectedChordID == chordID
        }
    }

    func setLeftFeedback(_ text: String) {
        leftFeedback = text
    }

    override func makeScene() -> SKScene {
        GuitarScene(
            session: self,
            chart: guitarChart,
            audio: audio
        )
    }
}
