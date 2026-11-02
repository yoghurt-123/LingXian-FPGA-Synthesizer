import Foundation

enum DrumKitInstrument: Int, CaseIterable, Identifiable {
    case kick = 0
    case snare = 1
    case closedHat = 2
    case openHat = 3
    case crash = 4
    case ride = 5
    case highTom = 6
    case midTom = 7
    case lowTom = 8

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .kick: return "底鼓"
        case .snare: return "军鼓"
        case .closedHat: return "闭镲"
        case .openHat: return "开镲"
        case .crash: return "Crash"
        case .ride: return "Ride"
        case .highTom: return "高 Tom"
        case .midTom: return "中 Tom"
        case .lowTom: return "低 Tom"
        }
    }

    var shortLabel: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .closedHat: return "闭"
        case .openHat: return "开"
        case .crash: return "Crash"
        case .ride: return "Ride"
        case .highTom: return "高"
        case .midTom: return "中"
        case .lowTom: return "低"
        }
    }

    var isCymbalLike: Bool {
        switch self {
        case .closedHat, .openHat, .crash, .ride:
            return true
        default:
            return false
        }
    }

    var futureFPGADrumID: Int {
        return rawValue
    }

    var keypadNumber: Int {
        FPGAKeyMap.drumPad(for: self).keypadNumber
    }

    var keypadLabel: String {
        "小键盘\(keypadNumber)"
    }

    var gridRow: Int {
        FPGAKeyMap.drumPad(for: self).gridRow
    }

    var gridColumn: Int {
        FPGAKeyMap.drumPad(for: self).gridColumn
    }

    /// BLE protocol v1 drum key order. This is deliberately not the same as
    /// the UI grid, keyboard keypad number, or enum rawValue.
    var bleProtocolKey: Int {
        switch self {
        case .kick: return 0
        case .snare: return 1
        case .closedHat: return 2
        case .openHat: return 3
        case .ride: return 4
        case .crash: return 5
        case .highTom: return 6
        case .lowTom: return 7
        case .midTom: return 8
        }
    }
}

struct DrumKitNote: Identifiable, Equatable {
    let id: Int
    let instrument: DrumKitInstrument
    let targetTime: TimeInterval
    let velocity: Int

    var lane: Int {
        instrument.rawValue
    }
}

struct DrumKitChart {
    let title: String
    let bpm: Int
    let notes: [DrumKitNote]
    let practiceChart: PracticeChart

    var lastNoteTime: TimeInterval {
        notes.map(\.targetTime).max() ?? 0
    }

    var durationText: String {
        "约 \(Int(ceil(lastNoteTime))) 秒"
    }

    static let builtIn = makeBuiltIn()

    private static func makeBuiltIn() -> DrumKitChart {
        let bpm: Int = 100
        let beatLength: TimeInterval = 60.0 / 100.0
        let startTime: TimeInterval = 2.0
        var rawEvents: [(beat: Double, instrument: DrumKitInstrument)] = []

        func add(_ beat: Double, _ instrument: DrumKitInstrument) {
            rawEvents.append((beat, instrument))
        }

        add(0, .kick)
        add(1, .snare)
        add(2, .closedHat)
        add(3, .highTom)
        add(4, .crash)
        add(5, .midTom)
        add(6, .openHat)
        add(6.5, .closedHat)
        add(7, .lowTom)
        add(8, .ride)

        add(9, .kick)
        add(10, .snare)
        add(11, .closedHat)
        add(12, .highTom)
        add(13, .openHat)
        add(14, .ride)
        add(15, .kick)
        add(15, .crash)

        add(16, .snare)
        add(17, .closedHat)
        add(18, .midTom)
        add(19, .lowTom)
        add(20, .kick)
        add(21, .snare)
        add(22, .openHat)
        add(22.5, .closedHat)
        add(23, .highTom)

        add(24, .crash)
        add(25, .midTom)
        add(26, .kick)
        add(27, .snare)
        add(28, .ride)
        add(29, .lowTom)
        add(30, .kick)
        add(30, .crash)
        add(31, .closedHat)

        add(32, .highTom)
        add(33, .midTom)
        add(34, .openHat)
        add(34.5, .closedHat)
        add(35, .snare)
        add(36, .lowTom)
        add(37, .ride)
        add(38, .kick)
        add(39, .snare)
        add(39, .crash)

        var timed: [(target: TimeInterval, instrument: DrumKitInstrument)] = []
        for event in rawEvents {
            let target: TimeInterval = startTime + event.beat * beatLength
            timed.append((target: target, instrument: event.instrument))
        }

        timed.sort { lhs, rhs in
            if lhs.target == rhs.target {
                return lhs.instrument.rawValue < rhs.instrument.rawValue
            }
            return lhs.target < rhs.target
        }

        var drumNotes: [DrumKitNote] = []
        var practiceNotes: [PracticeNote] = []
        for (index, item) in timed.enumerated() {
            let note = DrumKitNote(
                id: index,
                instrument: item.instrument,
                targetTime: item.target,
                velocity: 96
            )
            drumNotes.append(note)
            practiceNotes.append(
                PracticeNote(
                    id: index,
                    lane: note.lane,
                    targetTime: note.targetTime
                )
            )
        }

        let practiceChart = PracticeChart(
            title: "架子鼓入门 · 九鼓组合",
            bpm: bpm,
            countdownDuration: 3.0,
            previewDuration: 2.0,
            perfectWindow: 0.080,
            goodWindow: 0.160,
            laneCount: DrumKitInstrument.allCases.count,
            notes: practiceNotes
        )

        return DrumKitChart(
            title: "架子鼓入门 · 九鼓组合",
            bpm: bpm,
            notes: drumNotes,
            practiceChart: practiceChart
        )
    }
}
