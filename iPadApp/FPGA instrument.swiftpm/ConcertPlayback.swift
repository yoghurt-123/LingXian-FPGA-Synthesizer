import Foundation
import Combine

final class ConcertPlayback: ObservableObject {
    enum Phase: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    @Published private(set) var phase: Phase = .idle

    let song: ConcertSong
    private var accumulated: TimeInterval = 0
    private var anchor: TimeInterval?
    private var endTask: Task<Void, Never>?

    init(song: ConcertSong = .builtIn) {
        self.song = song
    }

    deinit {
        endTask?.cancel()
    }

    func currentTime() -> TimeInterval {
        let now: TimeInterval = ProcessInfo.processInfo.systemUptime
        guard phase == .playing, let anchor else {
            return min(max(accumulated, 0), song.duration)
        }
        let value: TimeInterval = accumulated + (now - anchor)
        return min(max(value, 0), song.duration)
    }

    func playPause() {
        switch phase {
        case .playing:
            pause()
        case .idle, .paused:
            play()
        case .finished:
            restart()
        }
    }

    func play() {
        guard phase != .playing else { return }
        if phase == .finished || accumulated >= song.duration {
            accumulated = 0
        }
        anchor = ProcessInfo.processInfo.systemUptime
        phase = .playing
        scheduleEnd()
    }

    func pause() {
        guard phase == .playing else { return }
        accumulated = currentTime()
        anchor = nil
        phase = .paused
        cancelEndTask()
    }

    func stop() {
        accumulated = 0
        anchor = nil
        phase = .idle
        cancelEndTask()
    }

    func restart() {
        accumulated = 0
        anchor = nil
        cancelEndTask()
        play()
    }

    private func finish() {
        accumulated = song.duration
        anchor = nil
        phase = .finished
        cancelEndTask()
    }

    private func cancelEndTask() {
        endTask?.cancel()
        endTask = nil
    }

    private func scheduleEnd() {
        cancelEndTask()
        let remaining: TimeInterval = max(0, song.duration - accumulated)
        guard remaining > 0 else {
            finish()
            return
        }
        endTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }
}
