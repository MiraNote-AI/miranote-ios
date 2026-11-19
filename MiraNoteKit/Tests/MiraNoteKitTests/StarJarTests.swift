import CoreGraphics
import XCTest
@testable import MiraNoteKit

final class StarJarTests: XCTestCase {
    // MARK: Moods wiped (#206)

    private func libraryFile(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moods-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testALibraryWithMoodsLoadsAndIsWrittenAgainWithout() throws {
        let page = #"{"id":"7B1C3A55-1A2B-4C3D-8E9F-001122334455","title":"Picnic","createdAt":700000000,"#
            + #""items":[],"hasBeenSaved":true,"mood":"joyful","moodTextHash":"abc"}"#
        let url = try libraryFile(#"{"collections":[{"id":"0A1C3A55-1A2B-4C3D-8E9F-001122334455","#
            + #""title":"Daily Log","memories":[\#(page)]}],"#
            + #""trash":[{"memory":\#(page),"collectionTitle":"Daily Log","deletedAt":700000001}]}"#)

        let library = FileCollectionStore(url: url).load()
        XCTAssertEqual(library.collections.first?.memories.first?.title, "Picnic")
        XCTAssertEqual(library.trash.first?.memory.title, "Picnic")
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(written.contains("mood"), "moods are wiped from the file, the bin's too")
        XCTAssertTrue(written.contains("Picnic"), "the pages are kept")
    }

    func testALibraryWithoutMoodsIsNotWrittenAgain() throws {
        let json = #"{"collections":[],"trash":[]}"#
        let url = try libraryFile(json)
        _ = FileCollectionStore(url: url).load()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), json)
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

    /// A page is a star once Save has filed it (#137): a draft never saved
    /// is none, and a saved page left as a draft keeps its star.
    func testADraftIsAStarOnlyOnceItHasBeenSaved() {
        let saved = Memory(title: "Saved", memoryDate: date(2026, 10, 2))
        let unsaved = Memory(title: "Never saved", memoryDate: date(2026, 10, 3), isDraft: true)
        let reopened = Memory(title: "Saved, now a draft", memoryDate: date(2026, 10, 4),
                              isDraft: true, hasBeenSaved: true)
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)
        XCTAssertEqual(StarJar.stars(in: library([saved, unsaved, reopened]), during: october).map(\.memory.title),
                       ["Saved", "Saved, now a draft"])
    }

    /// The jar steps past the current period only toward a star: a draft
    /// never saved, dated ahead, opens no later period.
    func testOnlyAStarDatedAheadOpensALaterPeriod() {
        let november = date(2026, 11, 1, 0, 0)
        let unsaved = Memory(title: "Plans", memoryDate: date(2026, 11, 5), isDraft: true)
        XCTAssertFalse(StarJar.hasStars(in: library([unsaved]), from: november))
        let saved = Memory(title: "Booked", memoryDate: date(2026, 11, 5))
        XCTAssertTrue(StarJar.hasStars(in: library([unsaved, saved]), from: november))
        XCTAssertFalse(StarJar.hasStars(in: library([saved]), from: date(2026, 12, 1, 0, 0)), "dated before")
    }

    func testPeriodLabels() {
        let english = Locale(identifier: "en_US")
        let october = JarPeriod.month.interval(containing: date(2026, 10, 3), calendar: calendar)
        XCTAssertEqual(JarPeriod.month.label(for: october, locale: english, calendar: calendar), "October 2026")
        let week = JarPeriod.week.interval(containing: date(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(JarPeriod.week.label(for: week, locale: english, calendar: calendar), "Oct 19 \u{2013} 25")
        let straddling = JarPeriod.week.interval(containing: date(2026, 10, 1), calendar: calendar)
        XCTAssertEqual(JarPeriod.week.label(for: straddling, locale: english, calendar: calendar),
                       "Sep 28 \u{2013} Oct 4")
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

    private func text(_ words: String, y top: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: words)), position: CGPoint(x: 180, y: top))
    }

    /// A page opened and left without a change keeps when it was saved:
    /// the jar drops in only what changed since the last visit.
    @MainActor
    func testFilingAnUnchangedPageKeepsItsSavedAt() throws {
        let viewModel = HomeViewModel(store: RecordingStore())
        let editor = CanvasViewModel(memory: Memory(items: [text("A picnic", y: 100)]))
        let first = editor.composedMemory()
        viewModel.file(first, underCollectionTitled: "Daily Log")
        let savedAt = try XCTUnwrap(viewModel.memory(first.id)?.savedAt)

        let reopened = CanvasViewModel(memory: try XCTUnwrap(viewModel.memory(first.id)))
        viewModel.file(reopened.composedMemory(), underCollectionTitled: "Daily Log")
        XCTAssertEqual(viewModel.memory(first.id)?.savedAt, savedAt, "only looked at")

        reopened.setText(itemID: reopened.items[0].id, to: "A picnic in the rain")
        viewModel.file(reopened.composedMemory(), underCollectionTitled: "Daily Log")
        XCTAssertNotEqual(viewModel.memory(first.id)?.savedAt, savedAt, "changed")
    }
}

private final class RecordingStore: CollectionStore, @unchecked Sendable {
    var saved: [MemoryLibrary] = []

    func load() -> MemoryLibrary { MemoryLibrary() }

    func save(_ library: MemoryLibrary) { saved.append(library) }
}
