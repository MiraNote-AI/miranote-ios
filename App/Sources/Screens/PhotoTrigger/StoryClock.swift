import MiraNoteKit
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

extension PhotoTriggerView {
    /// The photo's time on screen (`TriggerMemory.dwell`). UI tests that
    /// check the order pass `-TRIGGER-SLOW-STORY` (4x): XCUITest is too slow
    /// on an animating screen to keep up with 2-3 s.
    static func dwell(_ photo: TriggerMemory.Photo) -> TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TRIGGER-SLOW-STORY") {
            return TriggerMemory.dwell(for: photo) * 4
        }
        #endif
        return TriggerMemory.dwell(for: photo)
    }
}
