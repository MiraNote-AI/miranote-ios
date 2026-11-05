import XCTest
@testable import MiraNoteKit

/// Fails for the ids in `failing` (an iCloud-only photo, a Vision error, a
/// photo deleted after the listing); food for everything else.
final class FlakyAnalyzer: PhotoAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var failingIds: Set<String>
    private var calls: [String] = []

    init(failing: Set<String>) {
        failingIds = failing
    }

    var failing: Set<String> {
        get { lock.withLock { failingIds } }
        set { lock.withLock { failingIds = newValue } }
    }

    var analyzed: [String] { lock.withLock { calls } }

    func analyze(_ id: String) async -> PhotoAnalysis? {
        let fails = lock.withLock { () -> Bool in
            calls.append(id)
            return failingIds.contains(id)
        }
        guard !fails else { return nil }
        return PhotoAnalysis(id: id, labels: ["food"], broad: [.food_drink], faces: 0, aesthetics: nil,
                             isUtility: false, featurePrint: nil)
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

/// Photos whose analysis failed (handoff 7.1): left out of the run, and
/// tried again only after a day.
final class AnalysisFailureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_761_926_400)
    private var folder: URL!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var store: AnalysisStore { AnalysisStore(directory: folder) }

    private func rank(_ library: FakeLibrary, _ analyzer: PhotoAnalyzing, at date: Date) async -> TriggerRanking {
        await TriggerRanking.make(library: library, analyzer: analyzer, analyses: store, now: date,
                                  calendar: calendar, threshold: nil, groupingReport: nil, report: { _ in })
    }

    func testUnanalysedPhotosAreLeftOutOfGroupingAndPicks() async throws {
        let library = FakeLibrary(now: now, groups: [6])
        let analyzer = FlakyAnalyzer(failing: ["g0-1", "g0-4"])
        let ranking = await rank(library, analyzer, at: now)
        let fragment = try XCTUnwrap(ranking.fragments.first)
        let ids = Set(fragment.photos.map(\.id))
        XCTAssertFalse(ids.contains("g0-1"))
        XCTAssertFalse(ids.contains("g0-4"))
        XCTAssertEqual(fragment.uniqueCount, 4)
        XCTAssertFalse(ranking.preselect(fragment).contains { $0.id == "g0-1" || $0.id == "g0-4" })
        XCTAssertFalse(ranking.recentIds.contains("g0-1"))
    }

    func testNothingAnalysedGroupsNothing() async {
        let library = FakeLibrary(now: now, groups: [6])
        let analyzer = FlakyAnalyzer(failing: Set((0..<6).map { "g0-\($0)" }))
        let ranking = await rank(library, analyzer, at: now)
        XCTAssertEqual(ranking.fragments, [])
        XCTAssertEqual(ranking.groups, [])
    }

    func testAFailureWaitsADayBeforeItIsTriedAgain() async {
        let library = FakeLibrary(now: now, groups: [6])
        let analyzer = FlakyAnalyzer(failing: ["g0-2"])
        _ = await rank(library, analyzer, at: now)
        XCTAssertEqual(analyzer.analyzed.filter { $0 == "g0-2" }.count, 1)

        // The next foreground run, an hour later: not tried again.
        var progress: [TriggerProgress] = []
        _ = await TriggerRanking.make(library: library, analyzer: analyzer, analyses: store,
                                      now: now.addingTimeInterval(3600), calendar: calendar, threshold: nil,
                                      groupingReport: nil, report: { progress.append($0) })
        XCTAssertEqual(analyzer.analyzed.count, 6, "nothing analysed again")
        XCTAssertEqual(progress.last, .analyzing(done: 6, total: 6), "a skipped photo counts as done")

        // A day on, it is tried again; now it reads.
        analyzer.failing = []
        let later = await rank(library, analyzer, at: now.addingTimeInterval(86_400 + 60))
        XCTAssertEqual(analyzer.analyzed.filter { $0 == "g0-2" }.count, 2)
        XCTAssertTrue(later.fragments.first?.photos.contains { $0.id == "g0-2" } ?? false)
        XCTAssertEqual(store.failures(), [:], "a success clears the failure")
    }

    func testFailuresSurviveANewStore() async {
        let library = FakeLibrary(now: now, groups: [6])
        _ = await rank(library, FlakyAnalyzer(failing: ["g0-0"]), at: now)
        XCTAssertEqual(AnalysisStore(directory: folder).failures(), ["g0-0": now])
        XCTAssertFalse(AnalysisStore(directory: folder).analyzedIds().contains("g0-0"))
    }
}
