import Foundation

enum PianoKey: Int, CaseIterable, Identifiable {
    case c4 = 0
    case d4 = 1
    case e4 = 2
    case f4 = 3
    case g4 = 4
    case a4 = 5
    case b4 = 6
    case c5 = 7

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .c4: return "C4"
        case .d4: return "D4"
        case .e4: return "E4"
        case .f4: return "F4"
        case .g4: return "G4"
        case .a4: return "A4"
        case .b4: return "B4"
        case .c5: return "C5"
        }
    }

    var midiNote: Int {
        switch self {
        case .c4: return 60
        case .d4: return 62
        case .e4: return 64
        case .f4: return 65
        case .g4: return 67
        case .a4: return 69
        case .b4: return 71
        case .c5: return 72
        }
    }

    var frequency: Double {
        switch self {
        case .c4: return 261.63
        case .d4: return 293.66
        case .e4: return 329.63
        case .f4: return 349.23
        case .g4: return 392.00
        case .a4: return 440.00
        case .b4: return 493.88
        case .c5: return 523.25
        }
    }

    var keyboardLetter: String {
        switch self {
        case .c4: return "A"
        case .d4: return "S"
        case .e4: return "D"
        case .f4: return "F"
        case .g4: return "G"
        case .a4: return "H"
        case .b4: return "J"
        case .c5: return "K"
        }
    }
}

extension PracticeChart {
    static let piano = makePiano()

    private static func makePiano() -> PracticeChart {
        let bpm: Int = 90
        let beatLength: TimeInterval = 60.0 / 90.0
        let startTime: TimeInterval = 2.0
        var events: [(beat: Double, lanes: [Int])] = []

        func add(_ beat: Double, _ lanes: [Int]) {
            events.append((beat, lanes))
        }

        let opening: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1, 2, 3]
        for index in 0..<opening.count {
            let eventBeat: Double = Double(index)
            let lane: Int = opening[index]
            add(eventBeat, [lane])
        }

        add(16, [0])
        add(17, [2])
        add(18, [4])
        add(19, [6])
        add(20, [0, 4])
        add(21, [1])
        add(22, [3])
        add(23, [5])
        add(24, [2, 6])
        add(25, [4])
        add(26, [2])
        add(27, [0])

        add(28, [1])
        add(29, [3])
        add(30, [5])
        add(31, [7])
        add(32, [0, 3, 6])
        add(33, [2])
        add(34, [4])
        add(35, [6])
        add(36, [1, 4, 7])
        add(37, [0])
        add(38, [2])
        add(39, [5])
        add(40, [0, 4, 7])

        let holdPlan: [(beat: Double, lane: Int, durationBeats: Double)] = [
            (4, 4, 1.0),
            (8, 6, 1.0),
            (12, 2, 1.0),
            (16, 0, 2.0),
            (18, 4, 1.0),
            (22, 3, 2.0),
            (28, 1, 2.0),
            (31, 7, 1.5),
            (34, 4, 1.0),
            (37, 0, 1.0),
            (38, 2, 2.0)
        ]

        func holdDurationBeats(lane: Int, beat: Double) -> Double {
            holdPlan.first {
                $0.lane == lane && abs($0.beat - beat) < 0.001
            }?.durationBeats ?? 0
        }

        var timedNotes: [(target: TimeInterval, lane: Int, beat: Double)] = []
        for event in events {
            let target: TimeInterval = startTime + event.beat * beatLength
            for lane in event.lanes {
                timedNotes.append((target: target, lane: lane, beat: event.beat))
            }
        }

        timedNotes.sort { lhs, rhs in
            if lhs.target == rhs.target {
                return lhs.lane < rhs.lane
            }
            return lhs.target < rhs.target
        }

        var notes: [PracticeNote] = []
        for (index, item) in timedNotes.enumerated() {
            let duration = holdDurationBeats(lane: item.lane, beat: item.beat) * beatLength
            let note = PracticeNote(
                id: index,
                lane: item.lane,
                targetTime: item.target,
                duration: duration
            )
            notes.append(note)
        }

        return PracticeChart(
            title: "钢琴入门 · 八白键",
            bpm: bpm,
            countdownDuration: 3.0,
            previewDuration: 2.0,
            perfectWindow: 0.080,
            goodWindow: 0.160,
            laneCount: PianoKey.allCases.count,
            notes: notes
        )
    }
}
