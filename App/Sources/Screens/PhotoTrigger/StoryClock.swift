import Foundation

/// How long the current story photo has been on screen, across pauses (a
/// held finger, the menu). Equatable so a `.task(id:)` restarts its timer
/// whenever the clock starts, stops or resumes.
struct StoryClock: Equatable {
    /// Time banked before the latest pause.
    var banked: TimeInterval = 0
    /// When the clock last started running; nil while paused.
    var runningSince: Date?

    var isRunning: Bool { runningSince != nil }

    static func started(at now: Date = .now) -> StoryClock {
        StoryClock(banked: 0, runningSince: now)
    }

    func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    mutating func pause(at now: Date = .now) {
        guard isRunning else { return }
        banked = elapsed(at: now)
        runningSince = nil
    }

    mutating func resume(at now: Date = .now) {
        guard !isRunning else { return }
        runningSince = now
    }
}
