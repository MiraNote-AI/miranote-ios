import CoreGraphics
import XCTest
@testable import MiraNoteKit

final class StarJarTests: XCTestCase {
    // MARK: Mood on disk

    func testPagesSavedBeforeMoodsLoadAsNotJudged() throws {
        let legacy = Data(#"""
        {"id":"7B1C3A55-1A2B-4C3D-8E9F-001122334455","title":"Old page",
         "createdAt":700000000,"items":[]}
        """#.utf8)
        let memory = try JSONDecoder().decode(Memory.self, from: legacy)
        XCTAssertEqual(memory.title, "Old page")
        XCTAssertNil(memory.mood)
    }

    func testMoodRoundTripsAndAnUnknownOneReadsAsNotJudged() throws {
        let judged = Memory(title: "Picnic", mood: .joyful)
        let decoded = try JSONDecoder().decode(Memory.self, from: JSONEncoder().encode(judged))
        XCTAssertEqual(decoded.mood, .joyful)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(judged)) as? [String: Any])
        object["mood"] = "ecstatic"
        let later = try JSONDecoder().decode(Memory.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(later.mood, "a mood a later build added must not fail the library")
    }

    // MARK: Periods

    /// Weeks from Monday, in UTC, so the boundaries are the test's own.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func library(_ memories: [Memory]) -> MemoryLibrary {
        MemoryLibrary(collections: [MemoryCollection(title: "Daily Log", memories: memories)])
    }

    func testAWeekRunsFromTheCalendarsFirstWeekdayToTheNext() {
        let sunday = Memory(title: "Sunday night", memoryDate: date(2026, 10, 25, 23, 59))
        let monday = Memory(title: "Monday morning", memoryDate: date(2026, 10, 26, 0, 0))
        let week = JarPeriod.week.interval(containing: date(2026, 10, 28), calendar: calendar)

        XCTAssertEqual(StarJar.stars(in: library([sunday, monday]), during: week).map(\.memory.title),
                       ["Monday morning"])
        let before = JarPeriod.week.interval(shifting: week, by: -1, calendar: calendar)
        XCTAssertEqual(StarJar.stars(in: library([sunday, monday]), during: before).map(\.memory.title),
                       ["Sunday night"])
    }

    func testAMonthEndsAtMidnightOfTheNext() {
        let last = Memory(title: "Halloween", memoryDate: date(2026, 10, 31, 23, 59))
        let first = Memory(title: "November", memoryDate: date(2026, 11, 1, 0, 0))
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)

        XCTAssertEqual(StarJar.stars(in: library([first, last]), during: october).map(\.memory.title),
                       ["Halloween"])
        let november = JarPeriod.month.interval(shifting: october, by: 1, calendar: calendar)
        XCTAssertEqual(StarJar.stars(in: library([first, last]), during: november).map(\.memory.title),
                       ["November"])
    }

    func testStarsComeFromEveryJournalOldestFirstButNotFromTheBin() {
        let early = Memory(title: "Early", memoryDate: date(2026, 10, 2))
        let late = Memory(title: "Late", memoryDate: date(2026, 10, 20))
        let binned = Memory(title: "Binned", memoryDate: date(2026, 10, 5))
        let shelf = MemoryLibrary(
            collections: [
                MemoryCollection(title: "A", memories: [late]),
                MemoryCollection(title: "B", memories: [early])
            ],
            trash: [TrashedMemory(memory: binned, collectionTitle: "A")]
        )
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)
        let stars = StarJar.stars(in: shelf, during: october)
        XCTAssertEqual(stars.map(\.memory.title), ["Early", "Late"])
        XCTAssertEqual(stars.first?.collectionID, shelf.collections[1].id, "a star knows its journal")
    }

    func testPeriodLabels() {
        let english = Locale(identifier: "en_US")
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)
        XCTAssertEqual(JarPeriod.month.label(for: october, locale: english, calendar: calendar), "October 2026")
        let week = JarPeriod.week.interval(containing: date(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(JarPeriod.week.label(for: week, locale: english, calendar: calendar), "Oct 19 \u{2013} 25")
        let straddling = JarPeriod.week.interval(containing: date(2026, 10, 1), calendar: calendar)
        XCTAssertEqual(JarPeriod.week.label(for: straddling, locale: english, calendar: calendar), "Sep 28 \u{2013} Oct 4")
    }

    /// Chinese writes the dates its own way: "2026 year 10 month",
    /// "10 month 19 day - 25 day" (escaped: committed text stays ASCII).
    func testPeriodLabelsInChinese() {
        let chinese = Locale(identifier: "zh-Hans-CN")
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)
        XCTAssertEqual(JarPeriod.month.label(for: october, locale: chinese, calendar: calendar),
                       "2026\u{5E74}10\u{6708}")
        let week = JarPeriod.week.interval(containing: date(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(JarPeriod.week.label(for: week, locale: chinese, calendar: calendar),
                       "10\u{6708}19\u{65E5} \u{2013} 25\u{65E5}")
    }

    // MARK: Text to judge

    private func text(_ words: String, y: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: words)), position: CGPoint(x: 180, y: y))
    }

    func testMoodTextReadsWordsTopToBottomThenPhotosAndBackdrop() {
        let memory = Memory(
            items: [
                text("second line", y: 300),
                CanvasItem(content: .image(ImageRef(displayName: "p", summary: "Two friends at a picnic.")),
                           position: CGPoint(x: 180, y: 500)),
                CanvasItem(content: .sticker(GeneratedSticker(prompt: "cat", symbolName: "sparkles")),
                           position: CGPoint(x: 180, y: 50)),
                text("  A sunny day  ", y: 100),
                text("   ", y: 200)
            ],
            backgroundSummary: "a dusk sky"
        )
        XCTAssertEqual(memory.moodText, "A sunny day\nsecond line\nTwo friends at a picnic.\na dusk sky")
    }

    func testMoodTextIsEmptyForStickersAloneAndCapped() {
        let stickers = Memory(items: [
            CanvasItem(content: .sticker(GeneratedSticker(prompt: "cat", symbolName: "sparkles")),
                       position: .zero)
        ])
        XCTAssertEqual(stickers.moodText, "")

        let long = Memory(items: [text(String(repeating: "a", count: 5000), y: 10)])
        XCTAssertEqual(long.moodText.count, 2000)
    }

    func testMoodTextOfATitleAndBodyOnlyPage() {
        let legacy = Memory(title: "Slow morning", body: "good coffee")
        XCTAssertEqual(legacy.moodText, "Slow morning\ngood coffee")
    }

    // MARK: Writing the mood

    @MainActor
    func testSetMoodTouchesOnlyTheMoodOfTheLatestCopy() {
        let store = RecordingStore()
        let page = Memory(title: "Before", items: [text("first words", y: 100)])
        let viewModel = HomeViewModel(store: store)
        viewModel.file(page, underCollectionTitled: "Daily Log")

        // An edit filed while the mood was on its way.
        var edited = page
        edited.title = "After"
        edited.items = [text("newer words", y: 100)]
        viewModel.file(edited, underCollectionTitled: "Daily Log")

        viewModel.setMood(.calm, for: page.id)
        let stored = viewModel.memory(page.id)
        XCTAssertEqual(stored?.mood, .calm)
        XCTAssertEqual(stored?.title, "After", "the newer edit is kept")
        XCTAssertEqual(stored?.items, edited.items)
        XCTAssertEqual(store.saved.last?.collections.flatMap(\.memories).first?.mood, .calm, "persisted")
    }

    @MainActor
    func testSetMoodLeavesABinnedPageAlone() {
        let page = Memory(title: "Gone")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        let journal = viewModel.collections[0].id
        viewModel.deleteNote(page.id, from: journal)
        viewModel.setMood(.low, for: page.id)
        XCTAssertNil(viewModel.trash.first?.memory.mood)
        XCTAssertTrue(viewModel.collections[0].memories.isEmpty, "nothing comes back from the bin")
    }

    // MARK: Judging

    @MainActor
    func testJudgeAsksOneAtATimeAndWritesEachAnswer() async {
        let service = CountingMoodService(answer: .tender)
        let pages = (0..<4).map { Memory(title: "Page \($0)") }
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: pages)])
        let judge = MoodJudge(service: service, library: viewModel)

        judge.judge(pages.map(\.id))
        judge.judge(pages.map(\.id))
        await waitUntil { pages.allSatisfy { viewModel.memory($0.id)?.mood == .tender } }

        let counts = await service.counts()
        XCTAssertEqual(counts.calls, 4, "a page already waiting is not asked twice")
        XCTAssertEqual(counts.mostAtOnce, 1, "at most one request at a time")
    }

    @MainActor
    func testNothingToReadIsNeutralWithoutAsking() async {
        let service = CountingMoodService(answer: .joyful)
        let stickers = Memory(items: [
            CanvasItem(content: .sticker(GeneratedSticker(prompt: "cat", symbolName: "sparkles")), position: .zero)
        ])
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [stickers])])
        MoodJudge(service: service, library: viewModel).judge([stickers.id])
        await waitUntil { viewModel.memory(stickers.id)?.mood != nil }

        XCTAssertEqual(viewModel.memory(stickers.id)?.mood, .neutral)
        let counts = await service.counts()
        XCTAssertEqual(counts.calls, 0)
    }

    @MainActor
    func testAFailedAskLeavesTheMoodUnjudged() async {
        let service = CountingMoodService(answer: nil)
        let page = Memory(title: "Offline day")
        let viewModel = HomeViewModel(collections: [MemoryCollection(title: "Daily Log", memories: [page])])
        MoodJudge(service: service, library: viewModel).judge([page.id])
        await waitUntil { await service.counts().calls == 1 }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.memory(page.id)?.mood, "retried the next time the jar shows it")
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }
}

/// Answers every ask with `answer` (nil: fails) after a beat, counting the
/// asks and how many were in flight at once.
private actor CountingMoodService: MoodService {
    let answer: Mood?
    private var calls = 0
    private var inFlight = 0
    private var mostAtOnce = 0

    init(answer: Mood?) {
        self.answer = answer
    }

    func counts() -> (calls: Int, mostAtOnce: Int) { (calls, mostAtOnce) }

    func mood(for text: String) async throws -> Mood {
        calls += 1
        inFlight += 1
        mostAtOnce = max(mostAtOnce, inFlight)
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        guard let answer else { throw BackendError.unreachable }
        return answer
    }
}

private final class RecordingStore: CollectionStore, @unchecked Sendable {
    var saved: [MemoryLibrary] = []

    func load() -> MemoryLibrary { MemoryLibrary() }

    func save(_ library: MemoryLibrary) { saved.append(library) }
}
