import Foundation
import Combine
import SpriteKit

enum PracticePhase: Equatable {
    case idle
    case countdown
    case playing
    case paused
    case finished
}

enum PracticeJudgment: String, Equatable {
    case perfect = "Perfect"
    case good = "Good"
    case miss = "Miss"
    case empty = "空击"

    var isHit: Bool {
        self == .perfect || self == .good
    }
}

struct PracticeStats: Equatable {
    var score = 0
    var combo = 0
    var maxCombo = 0
    var perfect = 0
    var good = 0
    var miss = 0
    var emptyHits = 0

    var hitCount: Int {
        perfect + good
    }

    var resolvedCount: Int {
        perfect + good + miss
    }
}

enum PracticeHoldPhase: String, Equatable {
    case tap
    case holdStart
    case holdComplete
    case holdBreak
}

struct PracticeEvent: Equatable {
    let id: Int
    let lane: Int
    let judgment: PracticeJudgment
    let points: Int
    let noteID: Int?
    let holdPhase: PracticeHoldPhase
}

private struct ActiveHold {
    let noteID: Int
    let lane: Int
    let endTime: TimeInterval
    let judgment: PracticeJudgment
}

class PracticeSession: ObservableObject {
    let chart: PracticeChart
    weak var performanceController: PracticePerformanceController?
    var performancePageToken: UUID?

    @Published private(set) var phase: PracticePhase = .idle
    @Published private(set) var stats = PracticeStats()
    @Published private(set) var resolvedCount = 0
    @Published var speed: Double = 1.0
    @Published var reduceMotion: Bool = false

    private(set) var practiceTime: TimeInterval = 0
    private(set) var countdownRemaining: TimeInterval = 0
    private(set) var runID = 0

    private var resolvedNoteIDs: Set<Int> = []
    private var activeHolds: [Int: ActiveHold] = [:]
    private let holdEarlyTolerance: TimeInterval = 0.12
    private let holdLateTolerance: TimeInterval = 0.22
    private let holdCompleteBonus: Int = 40
    private var lastTick: TimeInterval?
    private var pausedDuringCountdown = false
    private var finishDeadline: TimeInterval?
    private let interruptionGap: TimeInterval = 1.0
    private var pendingEvents: [PracticeEvent] = []
    private var nextEventID = 0
    private var cachedScene: SKScene?

    var scene: SKScene {
        if let cachedScene {
            return cachedScene
        }
        let createdScene = makeScene()
        cachedScene = createdScene
        return createdScene
    }

    init(chart: PracticeChart = .builtIn) {
        self.chart = chart
    }

    func attachPerformance(_ controller: PracticePerformanceController?) {
        performanceController = controller
    }

    func releasePerformancePage() {
        guard let token = performancePageToken else { return }
        performanceController?.releaseCurrentPage(token: token, reason: .leavePage)
    }

    func makeScene() -> SKScene {
        RhythmScene(session: self)
    }

    var totalNotes: Int {
        chart.totalNotes
    }

    var progress: Double {
        guard totalNotes > 0 else { return 0 }
        return Double(resolvedCount) / Double(totalNotes)
    }

    var accuracy: Double {
        guard totalNotes > 0 else { return 0 }
        return Double(stats.hitCount) / Double(totalNotes)
    }

    var activeHoldCount: Int { activeHolds.count }

    func isHoldActive(noteID: Int) -> Bool {
        activeHolds.values.contains { $0.noteID == noteID }
    }

    func registerLaneRelease(lane: Int, at time: TimeInterval) {
        guard let hold = activeHolds.removeValue(forKey: lane) else { return }
        guard !resolvedNoteIDs.contains(hold.noteID) else { return }

        resolvedNoteIDs.insert(hold.noteID)
        resolvedCount = resolvedNoteIDs.count

        let error = time - hold.endTime
        let completed = error >= -holdEarlyTolerance && error <= holdLateTolerance
        var newStats = stats
        if completed {
            newStats.score += holdCompleteBonus
        } else {
            newStats.combo = 0
        }
        stats = newStats

        emit(
            lane: lane,
            judgment: completed ? hold.judgment : .miss,
            points: completed ? holdCompleteBonus : 0,
            noteID: hold.noteID,
            holdPhase: completed ? .holdComplete : .holdBreak
        )
        updateCompletion()
        finishIfNeeded()
    }

    func cancelPerformanceInput() {
        cancelActiveHolds()
    }

    private func cancelActiveHolds() {
        guard !activeHolds.isEmpty else { return }
        for (_, hold) in activeHolds {
            resolvedNoteIDs.insert(hold.noteID)
        }
        resolvedCount = resolvedNoteIDs.count
        activeHolds.removeAll(keepingCapacity: true)
        var newStats = stats
        newStats.combo = 0
        stats = newStats
        updateCompletion()
    }

    func start() {
        releasePerformancePage()
        activeHolds.removeAll(keepingCapacity: true)
        resolvedNoteIDs.removeAll(keepingCapacity: true)
        resolvedCount = 0
        stats = PracticeStats()
        pendingEvents.removeAll(keepingCapacity: true)
        practiceTime = 0
        countdownRemaining = chart.countdownDuration
        lastTick = nil
        pausedDuringCountdown = false
        finishDeadline = nil
        phase = .countdown
        runID &+= 1
    }

    func pause() {
        releasePerformancePage()
        cancelActiveHolds()
        switch phase {
        case .countdown:
            pausedDuringCountdown = true
            phase = .paused
            lastTick = nil
        case .playing:
            pausedDuringCountdown = false
            phase = .paused
            lastTick = nil
        default:
            break
        }
    }

    func resume() {
        guard phase == .paused else { return }
        phase = pausedDuringCountdown ? .countdown : .playing
        lastTick = nil
    }

    func advance(to now: TimeInterval) {
        guard phase == .countdown || phase == .playing else {
            lastTick = nil
            return
        }

        if let lastTick, now - lastTick > interruptionGap {
            pausedDuringCountdown = phase == .countdown
            phase = .paused
            self.lastTick = nil
            return
        }

        if let lastTick, now <= lastTick {
            return
        }

        let delta: TimeInterval
        if let lastTick {
            delta = max(0, now - lastTick)
        } else {
            delta = 0
        }
        lastTick = now
        let scaledDelta = delta * min(max(speed, 0.5), 1.25)

        if phase == .countdown {
            countdownRemaining -= scaledDelta
            if countdownRemaining <= 0 {
                let overflow = max(-countdownRemaining, 0)
                countdownRemaining = 0
                phase = .playing
                practiceTime += overflow
                markMissedNotes()
                updateActiveHolds()
                updateCompletion()
                finishIfNeeded()
            }
        } else {
            practiceTime += scaledDelta
            markMissedNotes()
            updateActiveHolds()
            updateCompletion()
            finishIfNeeded()
        }
    }

    func alignInput(to timestamp: TimeInterval) {
        guard phase == .playing else { return }
        guard let lastTick else { return }
        let elapsed: TimeInterval = timestamp - lastTick
        guard elapsed > 0, elapsed < interruptionGap else { return }
        advance(to: timestamp)
    }

    @discardableResult
    func registerHit(lane: Int, at time: TimeInterval) -> PracticeJudgment? {
        guard phase == .playing else { return nil }
        guard lane >= 0, lane < chart.laneCount else { return nil }

        guard let note = closestNote(in: lane, at: time) else {
            var newStats = stats
            newStats.emptyHits += 1
            stats = newStats
            emit(lane: lane, judgment: .empty, points: 0)
            return .empty
        }

        let error = abs(note.targetTime - time)
        let judgment: PracticeJudgment = error <= chart.perfectWindow ? .perfect : .good
        let points = judgment == .perfect ? 100 : 60

        if note.isHold {
            guard activeHolds[lane] == nil else { return nil }
            var holdStats = stats
            if judgment == .perfect {
                holdStats.perfect += 1
            } else {
                holdStats.good += 1
            }
            holdStats.score += points
            holdStats.combo += 1
            holdStats.maxCombo = max(holdStats.maxCombo, holdStats.combo)
            stats = holdStats
            activeHolds[lane] = ActiveHold(
                noteID: note.id,
                lane: lane,
                endTime: note.endTime,
                judgment: judgment
            )
            emit(
                lane: lane,
                judgment: judgment,
                points: points,
                noteID: note.id,
                holdPhase: .holdStart
            )
            return judgment
        }

        resolvedNoteIDs.insert(note.id)
        resolvedCount = resolvedNoteIDs.count

        var newStats = stats
        if judgment == .perfect {
            newStats.perfect += 1
        } else {
            newStats.good += 1
        }
        newStats.score += points
        newStats.combo += 1
        newStats.maxCombo = max(newStats.maxCombo, newStats.combo)
        stats = newStats

        emit(lane: lane, judgment: judgment, points: points, noteID: note.id)
        updateCompletion()
        return judgment
    }

    func isResolved(noteID: Int) -> Bool {
        resolvedNoteIDs.contains(noteID)
    }

    func nearestUnresolvedNote(in lane: Int, at time: TimeInterval) -> PracticeNote? {
        closestNote(in: lane, at: time)
    }

    @discardableResult
    func registerForcedMiss(noteID: Int, lane: Int) -> PracticeJudgment? {
        guard phase == .playing else { return nil }
        guard chart.notes.contains(where: { $0.id == noteID }) else { return nil }
        guard !resolvedNoteIDs.contains(noteID) else { return nil }

        resolvedNoteIDs.insert(noteID)
        resolvedCount = resolvedNoteIDs.count

        var newStats = stats
        newStats.miss += 1
        newStats.combo = 0
        stats = newStats

        emit(lane: lane, judgment: .miss, points: 0, noteID: noteID)
        updateCompletion()
        return .miss
    }

    func drainEvents() -> [PracticeEvent] {
        guard !pendingEvents.isEmpty else { return [] }
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return events
    }

    private func closestNote(in lane: Int, at time: TimeInterval) -> PracticeNote? {
        var best: PracticeNote?
        var bestError = TimeInterval.greatestFiniteMagnitude

        for note in chart.notes {
            guard note.lane == lane, !resolvedNoteIDs.contains(note.id) else { continue }
            guard !activeHolds.values.contains(where: { $0.noteID == note.id }) else { continue }
            let error = abs(note.targetTime - time)
            guard error <= chart.goodWindow else { continue }
            if error < bestError {
                best = note
                bestError = error
            }
        }

        return best
    }

    private func markMissedNotes() {
        let cutoff = practiceTime - chart.goodWindow
        var newStats = stats
        var changed = false

        for note in chart.notes {
            guard !resolvedNoteIDs.contains(note.id), note.targetTime < cutoff else { continue }
            guard !activeHolds.values.contains(where: { $0.noteID == note.id }) else { continue }
            resolvedNoteIDs.insert(note.id)
            newStats.miss += 1
            newStats.combo = 0
            changed = true
            emit(lane: note.lane, judgment: .miss, points: 0, noteID: note.id)
        }

        if changed {
            stats = newStats
            resolvedCount = resolvedNoteIDs.count
        }
    }

    private func updateActiveHolds() {
        guard phase == .playing, !activeHolds.isEmpty else { return }
        let expired = activeHolds.values.filter {
            practiceTime > $0.endTime + holdLateTolerance
        }
        guard !expired.isEmpty else { return }

        for hold in expired {
            activeHolds.removeValue(forKey: hold.lane)
            resolvedNoteIDs.insert(hold.noteID)
            emit(
                lane: hold.lane,
                judgment: .miss,
                points: 0,
                noteID: hold.noteID,
                holdPhase: .holdBreak
            )
        }
        resolvedCount = resolvedNoteIDs.count
        var newStats = stats
        newStats.combo = 0
        stats = newStats
    }

    private func updateCompletion() {
        guard phase == .playing, resolvedNoteIDs.count == chart.totalNotes else { return }
        if finishDeadline == nil {
            finishDeadline = practiceTime + 0.6
        }
    }

    private func finishIfNeeded() {
        guard phase == .playing, let finishDeadline, practiceTime >= finishDeadline else { return }
        releasePerformancePage()
        phase = .finished
        lastTick = nil
    }

    private func emit(
        lane: Int,
        judgment: PracticeJudgment,
        points: Int,
        noteID: Int? = nil,
        holdPhase: PracticeHoldPhase = .tap
    ) {
        pendingEvents.append(
            PracticeEvent(
                id: nextEventID,
                lane: lane,
                judgment: judgment,
                points: points,
                noteID: noteID,
                holdPhase: holdPhase
            )
        )
        nextEventID &+= 1
    }
}
