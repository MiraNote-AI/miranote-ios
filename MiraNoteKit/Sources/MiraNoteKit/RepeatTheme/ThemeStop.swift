import Foundation

public extension ThemeEngine {
    /// The time is up (a background task expired, the switch went off):
    /// every run asked for before this call -- the one in flight and the
    /// one waiting behind it -- stops at its next deadline check, as if its
    /// deadline had passed. What it saved stays; the next run goes on.
    nonisolated func stopEarly() {
        stops.bump()
    }
}

/// How many times `ThemeEngine.stopEarly` was called: a run compares the
/// count at its asking with the count now, from any thread.
final class StopCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func bump() {
        lock.withLock { count += 1 }
    }
}

/// A run's deadline as its checks read it: reached at `date` by `clock`,
/// whose time jumps past every deadline once `stopEarly` is called.
struct RunDeadline: Sendable {
    let date: Date
    let clock: @Sendable () -> Date

    var reached: Bool { clock() >= date }

    /// The same stop, `seconds` sooner.
    func earlier(by seconds: TimeInterval) -> RunDeadline {
        RunDeadline(date: date.addingTimeInterval(-seconds), clock: clock)
    }
}
