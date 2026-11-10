import XCTest
@testable import MiraNote

/// Must-fix 3: the background-time expiry handler waits for the scheduler
/// at most a bounded time, then ends the task whatever it did.
final class BoundedWaitTests: XCTestCase {
    func testQuickWorkFinishesInTime() {
        let finished = BoundedWait.run(atMost: BoundedWait.expiryGrace) {}
        XCTAssertTrue(finished)
    }

    func testSlowWorkIsNotWaitedFor() {
        let started = Date()
        let finished = BoundedWait.run(atMost: BoundedWait.expiryGrace) {
            try? await Task.sleep(for: .seconds(3))
        }
        XCTAssertFalse(finished)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "the handler returns within a second")
    }

    func testGraceIsAtMostOneSecond() {
        XCTAssertLessThanOrEqual(BoundedWait.expiryGrace, 1)
    }

    /// The main thread is the one blocked: the work must not need it.
    @MainActor
    func testWaitOnTheMainThreadDoesNotDeadlockOffMainWork() {
        let box = Box()
        let finished = BoundedWait.run(atMost: 1) { await box.set() }
        XCTAssertTrue(finished)
    }

    private actor Box {
        var value = false
        func set() { value = true }
    }
}
