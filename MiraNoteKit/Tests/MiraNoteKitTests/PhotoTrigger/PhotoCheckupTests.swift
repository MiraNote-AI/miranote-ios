import XCTest
@testable import MiraNoteKit

/// Answers `checkup` with an analysis and a theme vision, recording the
/// order it was asked in; fails for the ids in `failing`. `onCall` runs
/// before each answer (a test clock moved: a photo takes time).
final class CheckupAnalyzer: PhotoAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var checkupCalls: [String] = []
    private var analyzeCalls: [String] = []
    private var failingIds: Set<String>
    /// Ids answered as a document (a receipt photographed).
    var documents: Set<String> = []
    var onCall: (@Sendable () -> Void)?

    init(failing: Set<String> = []) {
        failingIds = failing
    }

    var failing: Set<String> {
        get { lock.withLock { failingIds } }
        set { lock.withLock { failingIds = newValue } }
    }

    var checkups: [String] { lock.withLock { checkupCalls } }
    var analyzed: [String] { lock.withLock { analyzeCalls } }

    static func vision(_ id: String) -> ThemeVision {
        ThemeVision(labels: [LabelScore(id: "food", confidence: 0.75)], print: [3, 4, 0, 12], printRevision: 2)
    }

    func analyze(_ id: String) async -> PhotoAnalysis? {
        lock.withLock { analyzeCalls.append(id) }
        return nil
    }

    func checkup(_ id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
        onCall?()
        let (fails, document) = lock.withLock { () -> (Bool, Bool) in
            checkupCalls.append(id)
            return (failingIds.contains(id), documents.contains(id))
        }
        guard !fails else { return nil }
        let analysis = PhotoAnalysis(id: id, labels: [document ? "document" : "food"],
                                     broad: [document ? .document : .food_drink], faces: 2, aesthetics: 0.25,
                                     isUtility: document, featurePrint: nil)
        return (analysis, Self.vision(id))
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

/// The one pass over the library both trigger modes share: each photo is
/// read once, newest first, and both stores are written from that read.
final class PhotoCheckupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_761_926_400)
    private var folder: URL!
    private let calendar: Calendar = {
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

    private var analyses: AnalysisStore { AnalysisStore(directory: folder.appendingPathComponent("analysis")) }
    private var themes: ThemePhotoStore { ThemePhotoStore(directory: folder.appendingPathComponent("themes")) }

    /// A camera photo taken `days` days before `now`, id "d<days>".
    private func asset(daysAgo days: Double, location: GeoPoint? = nil) -> LibraryAsset {
        LibraryAsset(id: "d\(days)", takenAt: now.addingTimeInterval(-days * 86_400), location: location,
                     isFavorite: false, isEdited: false, isScreenshot: false, isHidden: false, isVideo: false,
                     originalFilename: "IMG_0001.HEIC", burstId: nil)
    }

    /// One run as the next foreground run would start it: what is stored
    /// decides what is needed.
    private func run(_ assets: [LibraryAsset], _ analyzer: PhotoAnalyzing, at date: Date? = nil,
                     deadline: Date? = nil, clock: @escaping () -> Date = { Date() },
                     withThemes: Bool = true) async -> CheckupOutcome {
        let saved = analyses.analyzedIds()
        let stored = withThemes ? themes.loadAll() : [:]
        return await PhotoCheckupRunner.run(
            assets, needsV1: { !saved.contains($0) }, needsTheme: { withThemes && stored[$0] == nil },
            analyzer: analyzer, analyses: analyses, themes: withThemes ? themes : nil, now: date ?? now,
            calendar: calendar, deadline: deadline, clock: clock, report: { _ in })
    }

    func testCheckupGoesNewestFirst() async {
        let assets = [asset(daysAgo: 3), asset(daysAgo: 1), asset(daysAgo: 5), asset(daysAgo: 0.5),
                      asset(daysAgo: 2)]
        let analyzer = CheckupAnalyzer()
        let outcome = await run(assets, analyzer)
        XCTAssertEqual(analyzer.checkups, ["d0.5", "d1.0", "d2.0", "d3.0", "d5.0"])
        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.checkedThrough, now.addingTimeInterval(-5 * 86_400))
    }

    func testCheckupWritesBothStoresInOnePass() async throws {
        let point = GeoPoint(lat: 41.88, lon: -87.63)
        let assets = [asset(daysAgo: 1, location: point), asset(daysAgo: 2), asset(daysAgo: 3)]
        let analyzer = CheckupAnalyzer()
        analyzer.documents = ["d3.0"]
        let outcome = await run(assets, analyzer)

        XCTAssertEqual(analyzer.checkups.sorted(), ["d1.0", "d2.0", "d3.0"], "one checkup per photo")
        XCTAssertEqual(analyzer.analyzed, [], "no second read for V1")
        XCTAssertEqual(analyses.analyzedIds(), ["d1.0", "d2.0", "d3.0"])
        XCTAssertEqual(Set(outcome.analyses.keys), ["d1.0", "d2.0", "d3.0"])
        XCTAssertEqual(outcome.analyses["d1.0"]?.originalFilename, "IMG_0001.HEIC")

        let stored = themes.loadAll()
        XCTAssertEqual(Set(stored.keys), ["d1.0", "d2.0", "d3.0"])
        let first = try XCTUnwrap(stored["d1.0"])
        XCTAssertEqual(first.takenAt, now.addingTimeInterval(-86_400))
        XCTAssertEqual(first.location, point)
        XCTAssertEqual(first.labels, [LabelScore(id: "food", confidence: 0.75)])
        XCTAssertEqual(first.aesthetics, 0.25)
        XCTAssertEqual(first.faces, 2)
        XCTAssertTrue(first.isTheme)
        XCTAssertEqual(first.print, ThemePhoto.normalized([3, 4, 0, 12]))
        XCTAssertEqual(first.printRevision, 2)
        XCTAssertEqual(stored["d3.0"]?.isTheme, false, "a document is no theme photo")

        // Nothing is left to do: the next run reads nothing.
        _ = await run(assets, analyzer)
        XCTAssertEqual(analyzer.checkups.count, 3)
    }

    func testCheckupWithoutThemeVisionWritesNoThemePhoto() async {
        let assets = [asset(daysAgo: 1), asset(daysAgo: 2)]
        let analyzer = FlakyAnalyzer(failing: [])
        let outcome = await run(assets, analyzer)
        XCTAssertEqual(analyzer.analyzed.count, 2)
        XCTAssertEqual(analyses.analyzedIds(), ["d1.0", "d2.0"])
        XCTAssertEqual(themes.loadAll(), [:])
        XCTAssertTrue(outcome.finished)
    }

    func testCheckupResumesNewestFirstAfterInterruption() async {
        let assets = (1...6).map { asset(daysAgo: Double($0)) }.shuffled()
        let clock = TestClock(now)
        let analyzer = CheckupAnalyzer()
        analyzer.onCall = { clock.advance(1) }
        let first = await run(assets, analyzer, deadline: now.addingTimeInterval(3), clock: { clock.now })
        XCTAssertEqual(analyzer.checkups, ["d1.0", "d2.0", "d3.0"])
        XCTAssertFalse(first.finished)
        XCTAssertEqual(first.checkedThrough, now.addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(Set(themes.loadAll().keys), ["d1.0", "d2.0", "d3.0"], "what was read is kept")

        let second = await run(assets, analyzer, clock: { clock.now })
        XCTAssertEqual(analyzer.checkups, ["d1.0", "d2.0", "d3.0", "d4.0", "d5.0", "d6.0"])
        XCTAssertTrue(second.finished)
        XCTAssertEqual(second.checkedThrough, now.addingTimeInterval(-6 * 86_400))
        XCTAssertEqual(themes.loadAll().count, 6)
    }

    /// A2: a first run cut short still covers the 60 days V1 groups.
    func testCheckedThroughCoversSixtyDays() async throws {
        let assets = (0..<120).map { asset(daysAgo: Double($0) + 0.5) }
        let clock = TestClock(now)
        let analyzer = CheckupAnalyzer()
        analyzer.onCall = { clock.advance(1) }
        let outcome = await run(assets, analyzer, deadline: now.addingTimeInterval(61), clock: { clock.now })
        XCTAssertFalse(outcome.finished)
        XCTAssertEqual(analyzer.checkups.count, 61)
        let through = try XCTUnwrap(outcome.checkedThrough)
        XCTAssertLessThanOrEqual(through, now.addingTimeInterval(-60 * 86_400))
        XCTAssertEqual(through, now.addingTimeInterval(-60.5 * 86_400))
    }

    func testFailuresKeepV1RetryRule() async {
        let assets = (1...4).map { asset(daysAgo: Double($0)) }
        let analyzer = CheckupAnalyzer(failing: ["d2.0"])
        var outcome = await run(assets, analyzer)
        XCTAssertEqual(analyses.failures(), ["d2.0": now])
        XCTAssertNil(themes.loadAll()["d2.0"], "a failed read writes no theme photo")
        XCTAssertTrue(outcome.finished, "a photo waiting on its retry counts as done")

        // An hour on: left alone, and passed over by checkedThrough.
        outcome = await run(assets, analyzer, at: now.addingTimeInterval(3600))
        XCTAssertEqual(analyzer.checkups.filter { $0 == "d2.0" }.count, 1)
        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.checkedThrough, now.addingTimeInterval(-4 * 86_400))

        // A day on it is tried again, and the success clears the failure.
        analyzer.failing = []
        _ = await run(assets, analyzer, at: now.addingTimeInterval(PhotoCheckupRunner.retryAfter + 60))
        XCTAssertEqual(analyzer.checkups.filter { $0 == "d2.0" }.count, 2)
        XCTAssertEqual(analyses.failures(), [:])
        XCTAssertNotNil(themes.loadAll()["d2.0"])
    }

    func testFailuresAreWrittenDownInBatches() async {
        let assets = (1...25).map { asset(daysAgo: Double($0)) }
        let analyzer = CheckupAnalyzer(failing: Set(assets.map(\.id)))
        let store = analyses
        let batch = PhotoCheckupRunner.failuresBatch
        let seen = FlagBox(false)
        analyzer.onCall = {
            // Read just before the 21st photo: the first 20 are on disk.
            if analyzer.checkups.count == batch { seen.value = store.failures().count == batch }
        }
        _ = await run(assets, analyzer)
        XCTAssertTrue(seen.value)
        XCTAssertEqual(analyses.failures().count, 25)
    }

    // MARK: V1's ranking

    func testRankingWithAThemeStoreWritesThemeRecords() async {
        let library = FakeLibrary(now: now)
        let analyzer = CheckupAnalyzer()
        let ranking = await TriggerRanking.make(library: library, analyzer: analyzer, analyses: analyses, now: now,
                                                calendar: calendar, threshold: nil, groupingReport: nil,
                                                themes: themes, report: { _ in })
        XCTAssertEqual(ranking.analyses.count, 33)
        XCTAssertEqual(themes.loadAll().count, 33)
        let sortedDates = library.assetsList.sorted { $0.takenAt! > $1.takenAt! }.map(\.id)
        XCTAssertEqual(analyzer.checkups, sortedDates, "V1's window, newest first")

        _ = await TriggerRanking.make(library: library, analyzer: analyzer, analyses: analyses, now: now,
                                      calendar: calendar, threshold: nil, groupingReport: nil,
                                      themes: themes, report: { _ in })
        XCTAssertEqual(analyzer.checkups.count, 33, "nothing read twice")
    }

    func testRankingWithoutAThemeStoreWritesNone() async {
        let library = FakeLibrary(now: now)
        let analyzer = CheckupAnalyzer()
        let ranking = await TriggerRanking.make(library: library, analyzer: analyzer, analyses: analyses, now: now,
                                                calendar: calendar, threshold: nil, groupingReport: nil,
                                                report: { _ in })
        XCTAssertEqual(ranking.analyses.count, 33)
        XCTAssertEqual(themes.loadAll(), [:])
    }
}
