import XCTest
@testable import MiraNoteKit

final class SchedulerStateTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
    }

    func testThresholdStaleAfterAWeek() {
        var state = SchedulerState()
        XCTAssertTrue(state.needsThreshold(now: base))
        state.threshold = ThresholdResult(value: 7200, fallback: nil)
        state.thresholdComputedAt = base
        XCTAssertFalse(state.needsThreshold(now: base.addingTimeInterval(6.9 * 86_400)))
        XCTAssertTrue(state.needsThreshold(now: base.addingTimeInterval(7 * 86_400)))
    }

    func testRoundTripAndUpdate() throws {
        let store = SchedulerStateStore(file: tempFile())
        try store.update {
            $0.lastFullRunAt = self.base
            $0.threshold = ThresholdResult(value: 3600, fallback: .clamped)
            $0.outstanding["k"] = OutstandingJob(jobId: "j", submittedAt: self.base, slotDay: "2026-11-05")
        }
        let loaded = store.load()
        XCTAssertEqual(loaded.lastFullRunAt, base)
        XCTAssertEqual(loaded.threshold, ThresholdResult(value: 3600, fallback: .clamped))
        XCTAssertEqual(loaded.outstanding["k"]?.jobId, "j")
    }

    func testStateLoadsEmptyFromGarbage() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[".utf8).write(to: file)
        XCTAssertEqual(SchedulerStateStore(file: file).load(), SchedulerState())
    }
}
