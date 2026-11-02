import Foundation

enum GuitarLeftRequirement: Equatable {
    case fret(Int)
    case chord(Int)

    var fretNumber: Int? {
        if case .fret(let value) = self { return value }
        return nil
    }

    var chordID: Int? {
        if case .chord(let value) = self { return value }
        return nil
    }

    var chordName: String? {
        guard let id = chordID else { return nil }
        return FPGAKeyMap.guitarChords.first { $0.id == id }?.name
    }

    var displayText: String {
        switch self {
        case .fret(let value):
            return "\(value)品"
        case .chord(let value):
            let name = FPGAKeyMap.guitarChords.first { $0.id == value }?.name ?? "和弦"
            return "\(name) 和弦"
        }
    }
}

enum GuitarString: Int, CaseIterable, Identifiable {
    case highE = 1
    case b = 2
    case g = 3
    case d = 4
    case a = 5
    case lowE = 6

    var id: Int { rawValue }

    var displayIndex: Int {
        return 6 - rawValue
    }

    var openMidi: Int {
        switch self {
        case .highE: return 64
        case .b: return 59
        case .g: return 55
        case .d: return 50
        case .a: return 45
        case .lowE: return 40
        }
    }

    var openName: String {
        switch self {
        case .highE: return "E4"
        case .b: return "B3"
        case .g: return "G3"
        case .d: return "D3"
        case .a: return "A2"
        case .lowE: return "E2"
        }
    }

    var openFrequency: Double {
        return 440.0 * pow(2.0, Double(openMidi - 69) / 12.0)
    }

    var keyboardKey: String {
        if FPGAKeyMap.guitarStrings.indices.contains(displayIndex) {
            return FPGAKeyMap.guitarStrings[displayIndex].keyboardKey
        }
        return ""
    }

    var displayLabel: String {
        return "\(keyboardKey) · \(rawValue)弦 \(openName)"
    }

    var fpgaStringNumber: Int {
        return rawValue
    }

    static let displayOrder: [GuitarString] = [.lowE, .a, .d, .g, .b, .highE]
}

struct GuitarNote: Identifiable, Equatable {
    let id: Int
    let string: GuitarString
    let fret: Int
    let left: GuitarLeftRequirement
    let targetTime: TimeInterval
    let velocity: Int

    var lane: Int {
        string.displayIndex
    }

    var midiNote: Int {
        string.openMidi + fret
    }

    var frequency: Double {
        return 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }

    var pitchName: String {
        return GuitarNoteNaming.name(for: midiNote)
    }

    var hintText: String {
        if let chordName = left.chordName {
            return chordName
        }
        return "\(pitchName) · \(fret)品"
    }
}

struct GuitarChart {
    let title: String
    let bpm: Int
    let notes: [GuitarNote]
    let practiceChart: PracticeChart

    var lastNoteTime: TimeInterval {
        notes.map(\.targetTime).max() ?? 0
    }

    var durationText: String {
        "约 \(Int(ceil(lastNoteTime))) 秒"
    }

    var preparedMIDINotes: [Int] {
        var midiSet = Set<Int>()
        for string in GuitarString.allCases {
            for fret in 0...12 {
                midiSet.insert(string.openMidi + fret)
            }
        }
        for note in notes {
            midiSet.insert(note.midiNote)
            if let chordID = note.left.chordID,
               let chord = FPGAKeyMap.guitarChords.first(where: { $0.id == chordID }) {
                for tone in chord.tones {
                    midiSet.insert(tone.midiNote)
                }
            }
        }
        return midiSet.sorted()
    }

    static let builtIn = makeBuiltIn()

    private static func makeBuiltIn() -> GuitarChart {
        let bpm: Int = 72
        let beatLength: TimeInterval = 60.0 / 72.0
        let startTime: TimeInterval = 2.5
        var rawEvents: [(beat: Double, string: GuitarString, fret: Int, left: GuitarLeftRequirement)] = []

        func add(_ beat: Double, _ string: GuitarString, _ fret: Int) {
            rawEvents.append((beat, string, fret, .fret(fret)))
        }

        func addChord(_ beat: Double, _ string: GuitarString, _ chordID: Int) {
            rawEvents.append((beat, string, 0, .chord(chordID)))
        }

        let openPattern: [GuitarString] = [.lowE, .a, .d, .g, .b, .highE, .b, .g]
        for (index, string) in openPattern.enumerated() {
            add(Double(index), string, 0)
        }

        for (index, string) in openPattern.enumerated() {
            add(10 + Double(index), string, 2)
        }

        addChord(20, .a, 0)
        addChord(22, .lowE, 1)
        addChord(24, .d, 2)
        addChord(26, .a, 3)

        var timed: [(target: TimeInterval, string: GuitarString, fret: Int, left: GuitarLeftRequirement)] = []
        for event in rawEvents {
            let target: TimeInterval = startTime + event.beat * beatLength
            timed.append((target: target, string: event.string, fret: event.fret, left: event.left))
        }

        timed.sort { lhs, rhs in
            if lhs.target == rhs.target {
                return lhs.string.displayIndex < rhs.string.displayIndex
            }
            return lhs.target < rhs.target
        }

        var guitarNotes: [GuitarNote] = []
        var practiceNotes: [PracticeNote] = []
        for (index, item) in timed.enumerated() {
            let note = GuitarNote(
                id: index,
                string: item.string,
                fret: item.fret,
                left: item.left,
                targetTime: item.target,
                velocity: 92
            )
            guitarNotes.append(note)
            practiceNotes.append(
                PracticeNote(
                    id: index,
                    lane: note.lane,
                    targetTime: note.targetTime
                )
            )
        }

        let practiceChart = PracticeChart(
            title: "电吉他简化节奏 · 空弦与2品",
            bpm: bpm,
            countdownDuration: 3.0,
            previewDuration: 3.4,
            perfectWindow: 0.10,
            goodWindow: 0.20,
            laneCount: GuitarString.allCases.count,
            notes: practiceNotes
        )

        return GuitarChart(
            title: "电吉他简化节奏 · 空弦与2品",
            bpm: bpm,
            notes: guitarNotes,
            practiceChart: practiceChart
        )
    }
}
enum GuitarNoteNaming {
    private static let names: [String] = [
        "C", "C#", "D", "D#", "E", "F",
        "F#", "G", "G#", "A", "A#", "B"
    ]

    static func name(for midi: Int) -> String {
        let safeMidi: Int = max(0, midi)
        let noteIndex: Int = safeMidi % 12
        let octave: Int = safeMidi / 12 - 1
        return "\(names[noteIndex])\(octave)"
    }
}
