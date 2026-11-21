import Foundation
import XCTest
@testable import MiraNoteKit

/// The run around the asks: the window, the checkup, the moments cap,
/// deleted photos and overlapping runs (A1-A4, I4).
final class ThemeEngineRunTests: XCTestCase {
    private var harness: ThemeHarness!

    override func setUp() {
        super.setUp()
        harness = ThemeHarness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    private func run(_ engine: ThemeEngine, deadline: Date? = nil) async -> ThemeRunReport {
        await engine.run(trigger: .foreground, deadline: deadline)
    }

    func testWindowStartsOneTwentyDaysBeforeFirstRunAndOnlyGrows() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("old", base: 1, days: [125, 126])
        let expected = harness.calendar.startOfDay(for: harness.day(120))
        _ = await run(harness.engine())
        XCTAssertEqual(harness.library.sinceDates, [expected])
        XCTAssertEqual(harness.window.load()?.start, expected)
        XCTAssertFalse(harness.analyzer.checked.contains { $0.hasPrefix("old-") })

        // A month later, a fresh engine on the same stores: the start stays.
        harness.clock.advance(30 * 86_400)
        _ = await run(harness.engine())
        XCTAssertEqual(harness.library.sinceDates, [expected, expected])
        XCTAssertEqual(harness.window.load()?.start, expected)
    }

    func testClustersOnceSixtyDaysChecked() async {
        harness.addTheme("x", base: 0, days: Array(1...8))
        for day in 9...120 {
            harness.add("f-\(day)", at: harness.day(day))
            harness.analyzer.utility.insert("f-\(day)")
        }
        let clock = harness.clock
        harness.analyzer.onCheckup = { _ in clock.advance(60) }
        let engine = harness.engine()

        // 30 photos (30 days back): not yet 60 days, so no piles. The
        // checkup stops a minute before the deadline (time to cluster).
        let reserve = ThemeEngine.clusterReserve
        var report = await run(engine, deadline: clock.now.addingTimeInterval(30 * 60 + reserve))
        XCTAssertEqual(report.checkedNew, 30)
        XCTAssertTrue(report.piles.isEmpty)
        XCTAssertEqual(report.asked, 0)
        XCTAssertEqual(report.moments, 0)

        // 40 more, newest first: 70 days back is enough to cluster.
        report = await run(engine, deadline: clock.now.addingTimeInterval(40 * 60 + reserve))
        XCTAssertEqual(report.checkedNew, 40)
        XCTAssertEqual(harness.analyzer.checked.last, "f-70")
        XCTAssertEqual(report.piles.count, 1)
        XCTAssertEqual(report.asked, 1)
    }

    func testDeadlineStopsBeforeClustering() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let clock = harness.clock
        harness.analyzer.onCheckup = { id in if id == "x-6" { clock.advance(3600) } }
        let report = await run(harness.engine(), deadline: clock.now.addingTimeInterval(120))
        XCTAssertEqual(report.checkedNew, 6, "the checkup itself finished")
        XCTAssertTrue(report.failures.contains("Deadline reached before clustering"))
        XCTAssertTrue(report.piles.isEmpty)
        XCTAssertEqual(report.asked, 0)
    }

    func testDeadlineStopsTheAsksLeft() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("y", base: 1, days: Array(1...6))
        let clock = harness.clock
        harness.client.onRoundOne = { clock.advance(7200) }
        let engine = harness.engine()
        let report = await run(engine, deadline: clock.now.addingTimeInterval(3600))
        XCTAssertEqual(report.piles.count, 2)
        XCTAssertEqual(report.asked, 1)
        XCTAssertTrue(report.failures.contains("Deadline reached: 1 asks left"))
        XCTAssertEqual(harness.themes.load().count, 1)

        _ = await run(engine)
        XCTAssertEqual(harness.client.roundOneRequests.count, 2, "the pile left is asked next run")
        XCTAssertEqual(harness.themes.load().count, 2)
    }

    func testMomentsOverCapDropOldest() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.addTheme("y", base: 1, days: Array(30...35))
        harness.momentsCap = 6
        let report = await run(harness.engine())
        XCTAssertEqual(report.moments, 6)
        XCTAssertEqual(report.piles.count, 1)
        XCTAssertTrue(report.piles[0].momentIds.allSatisfy { $0.hasPrefix("x-") }, "the oldest moments go")

        harness.momentsCap = 5000
        let uncapped = await run(harness.engine())
        XCTAssertEqual(uncapped.moments, 12)
        XCTAssertEqual(uncapped.piles.count, 2)
    }

    func testPrintRevisionChangeRechecksAll() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        XCTAssertEqual(harness.analyzer.checked.count, 6)
        _ = await run(engine)
        XCTAssertEqual(harness.analyzer.checked.count, 6, "nothing new, nothing read")

        // The OS changed the print revision: the next new photo shows it.
        harness.analyzer.revision = 2
        harness.addTheme("x", base: 0, days: [7])
        let report = await run(engine)
        XCTAssertEqual(harness.analyzer.checked.count, 13, "the new photo, then every old one again")
        XCTAssertEqual(report.checkedNew, 7)
        XCTAssertEqual(harness.window.load()?.printRevision, 2)
        XCTAssertTrue(harness.photos.loadAll().values.allSatisfy { $0.printRevision == 2 })
        XCTAssertEqual(report.piles.count, 1)
    }

    func testRevisionChangeCutShortDoesNotCluster() async {
        // A theme 70-75 days back: re-reading two of it already gets the
        // checkup past 60 days.
        harness.addTheme("x", base: 0, days: Array(70...75))
        let engine = harness.engine()
        _ = await run(engine)
        let before = harness.bigRow(with: "x-70")
        XCTAssertEqual(before?.members.count, 6)

        // New revision; time for 3 reads: the new n-1, then x-70 and x-71 again.
        harness.analyzer.revision = 2
        harness.add("n-1", at: harness.day(1))
        harness.analyzer.utility.insert("n-1")
        let clock = harness.clock
        harness.analyzer.onCheckup = { _ in clock.advance(60) }
        let cut = await run(engine, deadline: clock.now.addingTimeInterval(3 * 60 + ThemeEngine.clusterReserve))
        XCTAssertEqual(cut.checkedNew, 3)
        XCTAssertTrue(cut.piles.isEmpty, "no piles from 2 re-read photos")
        XCTAssertTrue(cut.failures.contains { $0.hasPrefix("Print revision changed") })
        XCTAssertEqual(harness.bigRow(with: "x-70"), before, "the old theme is not frozen")

        let done = await run(engine)
        XCTAssertEqual(done.piles.count, 1)
        XCTAssertEqual(harness.bigRow(with: "x-70")?.status, .active)
        XCTAssertEqual(harness.bigRow(with: "x-70")?.members.count, 6)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
    }

    func testNoVisionPhotosAreNotRecheckedEveryRun() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        harness.analyzer.noVision = ["x-1"]
        let engine = harness.engine()
        _ = await run(engine)
        _ = await run(engine)
        XCTAssertEqual(harness.analyzer.checked.filter { $0 == "x-1" }.count, 1)
        XCTAssertNil(harness.photos.loadAll()["x-1"])
    }

    func testUndatedPhotosNeedNoThemeRecord() async {
        // A library that hands out an undated photo.
        harness.addTheme("x", base: 0, days: Array(1...6))
        let undated = UndatedLibrary(base: harness.library)
        let deps = harness.deps
        let engine = ThemeEngine(ThemeDependencies(
            library: undated, analyzer: deps.analyzer, analyses: deps.analyses, photos: deps.photos,
            themes: deps.themes, rounds: deps.rounds, window: deps.window, runs: deps.runs, client: deps.client,
            imageData: deps.imageData, now: deps.now, calendar: deps.calendar, momentsCap: deps.momentsCap))
        _ = await engine.run(trigger: .foreground, deadline: nil)
        _ = await engine.run(trigger: .foreground, deadline: nil)
        XCTAssertFalse(harness.analyzer.checked.contains("undated"))
    }

    func testEmptyFetchDoesNotPruneThemes() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        _ = await run(engine)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.members.count, 6)
        let all = harness.library.assetsList

        // Access taken away: an empty fetch is never "everything deleted".
        harness.library.assetsList = []
        let report = await run(engine)
        XCTAssertFalse(report.failures.isEmpty)
        XCTAssertEqual(harness.photos.loadAll().count, 6)
        XCTAssertEqual(harness.bigRow(with: "x-1")?.members.count, 6)

        // x-1 really deleted: it leaves the records and every list.
        harness.library.assetsList = all.filter { $0.id != "x-1" }
        _ = await run(engine)
        XCTAssertNil(harness.photos.loadAll()["x-1"])
        let row = harness.bigRow(with: "x-2")
        XCTAssertEqual(row?.members.count, 5)
        XCTAssertFalse(row?.members.contains("x-1") ?? true)
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
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

    func testOverlappingThemeRunsCoalesce() async throws {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let gate = CheckupGate()
        harness.analyzer.onCheckup = { _ in await gate.wait() }
        let engine = harness.engine()

        let first = Task { await engine.run(trigger: .foreground, deadline: nil) }
        try await waitUntil { gate.isWaiting }
        let second = Task { await engine.run(trigger: .background, deadline: nil) }
        let third = Task { await engine.run(trigger: .debug, deadline: nil) }
        try await waitUntil { await engine.waitingCallers == 2 }
        gate.release()

        let one = await first.value
        let two = await second.value
        let three = await third.value
        XCTAssertEqual(one.trigger, .foreground)
        XCTAssertEqual(two.trigger, .background, "the follow-up runs for the first caller that waited")
        XCTAssertEqual(two, three, "every waiting caller gets the follow-up's report")
        XCTAssertEqual(harness.library.sinceDates.count, 2, "one run, then one follow-up")
        XCTAssertEqual(harness.client.roundOneRequests.count, 1)
    }

    func testStopEarlyEndsTheRunInFlightAsAtItsDeadline() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        // A background task's time runs out while the third photo is read.
        harness.analyzer.onCheckup = { id in if id == "x-3" { engine.stopEarly() } }
        let stopped = await engine.run(trigger: .background, deadline: nil)
        XCTAssertEqual(stopped.checkedNew, 3)
        XCTAssertTrue(stopped.piles.isEmpty)
        XCTAssertEqual(stopped.asked, 0)
        XCTAssertFalse(stopped.failures.isEmpty)

        // A run asked for after the stop is not stopped by it.
        harness.analyzer.onCheckup = nil
        let next = await engine.run(trigger: .foreground, deadline: nil)
        XCTAssertEqual(next.checkedNew, 3)
        XCTAssertEqual(next.piles.count, 1)
        XCTAssertEqual(next.asked, 1)
    }

    func testRunReportsAreKeptLastTwenty() async {
        harness.addTheme("x", base: 0, days: Array(1...6))
        let engine = harness.engine()
        for _ in 0..<22 { _ = await run(engine) }
        let runs = harness.runs.load()
        XCTAssertEqual(runs.count, 20)
        XCTAssertEqual(runs.last?.photos, 6)
        XCTAssertEqual(runs.last?.piles.first?.momentIds.count, 6)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.runs.count, 20)
        XCTAssertEqual(snapshot.themes.count, 1)
        XCTAssertEqual(snapshot.rounds.count, 1)
        XCTAssertGreaterThanOrEqual(runs.last?.clusterMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(runs.last?.checkupMs ?? -1, 0)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<5000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out")
    }
}

/// `base` plus one photo without a capture date.
private struct UndatedLibrary: PhotoLibraryReading {
    let base: FakeLibrary

    func requestAccess() async -> PhotoAccess { .full }
    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset] {
        let undated = LibraryAsset(id: "undated", takenAt: nil, location: nil, isFavorite: false, isEdited: false,
                                   isScreenshot: false, isHidden: false, isVideo: false,
                                   originalFilename: "IMG_0002.HEIC", burstId: nil)
        return await base.assets(since: date, knownFilenames: knownFilenames) + [undated]
    }
    func uploadData(for id: String) async -> Data? { nil }
}
