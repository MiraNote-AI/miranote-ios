import Foundation
import XCTest
@testable import MiraNoteKit

/// What a run must not undo: a block made while it is in flight, and the
/// sensitive and blocked themes of photos the fetch cannot see (D5, F7).
final class ThemeEngineKeepTests: XCTestCase {
    private var harness: ThemeHarness!

    override func setUp() {
        super.setUp()
        harness = ThemeHarness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    private func run(_ engine: ThemeEngine) async -> ThemeRunReport {
        await engine.run(trigger: .foreground, deadline: nil)
    }

    /// Under "Select Photos" a photo missing from the fetch may only be
    /// hidden from the app: nothing is pruned, so a blocked theme stays
    /// blocked with its photos and none of them is read or sent again.
    func testLimitedAccessPrunesNothing() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("y", base: 1, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        let blocked = try XCTUnwrap(harness.bigRow(with: "x-1")?.id)
        await engine.block(blocked)
        let all = harness.library.assetsList
        let checked = harness.analyzer.checked.count

        harness.library.access = .limited
        harness.library.assetsList = all.filter { $0.id.hasPrefix("y-") }
        _ = await run(engine)
        XCTAssertEqual(harness.photos.loadAll().count, 12, "no theme record dropped")
        let row = try XCTUnwrap(harness.themes.load().first { $0.id == blocked })
        XCTAssertEqual(row.status, .blocked)
        XCTAssertEqual(row.members.count, 6)

        // Full access is back: the photos were there all along.
        harness.library.access = .full
        harness.library.assetsList = all
        _ = await run(engine)
        XCTAssertEqual(harness.analyzer.checked.count, checked, "nothing read again")
        XCTAssertEqual(harness.themes.load().first { $0.id == blocked }?.status, .blocked)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2, "the blocked pile is not sent again")
    }

    /// "Not this theme" while a run is in flight: on disk at once, not after
    /// the run (the app may be swiped away first), and the run's later saves
    /// of the rows it read before keep it.
    func testBlockDuringARunIsWrittenAtOnceAndSurvivesTheRun() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        let id = try XCTUnwrap(harness.bigRow(with: "x-1")?.id)

        // The theme grows (a re-ask is due); the run holds in its checkup.
        harness.addBurst("x", days: Array(1...6), extra: 1)
        let gate = CheckupGate()
        harness.analyzer.onCheckup = { _ in await gate.wait() }
        let running = Task { await engine.run(trigger: .foreground, deadline: nil) }
        try await waitUntil { gate.isWaiting }

        let blocking = Task { await engine.block(id) }
        try await waitUntil { self.harness.bigRow(with: "x-1")?.status == .blocked }
        gate.release()
        _ = await running.value
        await blocking.value
        XCTAssertEqual(harness.bigRow(with: "x-1")?.status, .blocked, "the run's saves keep the block")
        XCTAssertEqual(harness.bigRow(with: "x-1")?.members.count, 12, "the run's own changes are saved")
        XCTAssertEqual(harness.client.roundOneRequests.count, 1, "a theme blocked mid-run is not asked")

        // Once no run is in flight, an unblock is not undone by the old block.
        await engine.unblock(id)
        _ = await run(engine)
        XCTAssertNotEqual(harness.bigRow(with: "x-1")?.status, .blocked)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<5000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out")
    }
}
