import Foundation
import UIKit

enum DrumLane: Int, CaseIterable, Identifiable {
    case kick = 0
    case snare = 1
    case hihat = 2
    case crash = 3

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .kick: return "底鼓"
        case .snare: return "军鼓"
        case .hihat: return "闭镲"
        case .crash: return "Crash"
        }
    }

    var englishName: String {
        switch self {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .hihat: return "HI-HAT"
        case .crash: return "CRASH"
        }
    }

    var color: UIColor {
        switch self {
        case .kick:
            return PixelPalette.accentUI
        case .snare:
            return PixelPalette.goodUI
        case .hihat:
            return PixelPalette.goodUI
        case .crash:
            return PixelPalette.accentDarkUI
        }
    }
}

struct PracticeNote: Identifiable, Equatable {
    let id: Int
    let lane: Int
    let targetTime: TimeInterval
    let duration: TimeInterval

    init(id: Int, lane: Int, targetTime: TimeInterval, duration: TimeInterval = 0) {
        self.id = id
        self.lane = lane
        self.targetTime = targetTime
        self.duration = max(0, duration)
    }

    var endTime: TimeInterval { targetTime + duration }
    var isHold: Bool { duration > 0.001 }

    var drumLane: DrumLane {
        DrumLane(rawValue: lane) ?? .kick
    }
}

struct PracticeChart {
    let title: String
    let bpm: Int
    let countdownDuration: TimeInterval
    let previewDuration: TimeInterval
    let perfectWindow: TimeInterval
    let goodWindow: TimeInterval
    let laneCount: Int
    let notes: [PracticeNote]

    var totalNotes: Int { notes.count }

    var lastNoteTime: TimeInterval {
        notes.map(\.endTime).max() ?? 0
    }

    var durationText: String {
        "约 \(Int(ceil(lastNoteTime))) 秒"
    }

    static let builtIn = makeBuiltIn()

    private static func makeBuiltIn() -> PracticeChart {
        let beat: TimeInterval = 0.6
        let startTime: TimeInterval = 2.0
        var events: [(beat: Double, lanes: [Int])] = []

        func single(_ beat: Double, _ lane: Int) {
            events.append((beat, [lane]))
        }

        func double(_ beat: Double, _ lanes: [Int]) {
            events.append((beat, lanes))
        }

        let opening = [0, 1, 2, 1, 0, 2, 1, 3]
        for (index, lane) in opening.enumerated() {
            single(Double(index), lane)
        }

        single(8, 0)
        single(8.5, 1)
        single(9, 2)
        single(9.5, 1)
        single(10, 0)
        single(11, 2)
        single(12, 1)
        single(13, 3)
        single(14, 0)
        single(14.5, 1)
        single(15, 2)
        single(15.5, 1)

        single(16, 0)
        single(17, 1)
        single(18, 2)
        single(19, 3)
        double(20, [0, 2])
        single(21, 1)
        single(22, 0)
        single(22.5, 2)
        double(23, [1, 3])
        single(24, 1)
        single(25, 3)
        double(26, [0, 3])
        single(27, 2)
        single(28, 0)
        single(28.5, 1)
        double(29, [1, 2])
        single(30, 3)
        single(31, 2)
        single(31.5, 0)
        double(32, [1, 2])

        var timedEvents: [(target: TimeInterval, lane: Int)] = []
        for event in events {
            let target: TimeInterval = startTime + event.beat * beat
            for lane in event.lanes {
                timedEvents.append((target: target, lane: lane))
            }
        }
        timedEvents.sort { lhs, rhs in
            if lhs.target == rhs.target { return lhs.lane < rhs.lane }
            return lhs.target < rhs.target
        }
        var sortedNotes: [PracticeNote] = []
        for (index, item) in timedEvents.enumerated() {
            let note = PracticeNote(id: index, lane: item.lane, targetTime: item.target)
            sortedNotes.append(note)
        }

        return PracticeChart(
            title: "四轨基本功 · 单轨与双押",
            bpm: 100,
            countdownDuration: 3.0,
            previewDuration: 2.0,
            perfectWindow: 0.080,
            goodWindow: 0.160,
            laneCount: 4,
            notes: sortedNotes
        )
    }
}
