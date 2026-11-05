import MiraNoteKit
import XCTest
@testable import MiraNote

/// The ending's Keep, from the story to its canvas draft: the draft opens
/// only over the story that asked for it, never over a cover opened since,
/// and no push opens while one cover gives way to the other.
@MainActor
final class TriggerKeepTests: XCTestCase {
    /// HomeFlow's covers, as the keep sees them.
    private final class Screen {
        enum Cover: Equatable {
            case story(UUID)
            case editor
            case draft
        }

        var cover: Cover?
        var closes = 0
        var opened: [TriggerDraft] = []
        var discarded: [TriggerDraft] = []

        var covers: TriggerKeep.Covers {
            TriggerKeep.Covers(
                story: { [unowned self] in
                    if case .story(let id) = cover { return id }
                    return nil
                },
                isEmpty: { [unowned self] in cover == nil },
                close: { [unowned self] in
                    closes += 1
                    cover = nil
                },
                open: { [unowned self] in
                    opened.append($0)
                    cover = .draft
                },
                discard: { [unowned self] in discarded.append($0) }
            )
        }
    }

    private let draft: TriggerDraft = {
        let photos = ["P1", "P2", "P3"].map { TriggerMemory.Photo(id: $0, takenAt: .now, isPeak: $0 == "P1") }
        let memory = TriggerMemory(
            id: "m", date: "2026-10-18", daypart: .afternoon,
            push: .init(title: "t", body: "b", coverPhotoId: "P1"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "10.18", detail: "",
                          questions: [.init(text: "q", type: "one_word", source: "fallback_B1")], ctaLabel: "c"))
        return TriggerDraftBuilder.draft(memory: memory, imageFiles: [:], detailFont: "")
    }()

    func testKeepOpensTheDraftOverItsStory() async {
        let story = UUID()
        let screen = Screen()
        screen.cover = .story(story)
        await TriggerKeep(gap: .milliseconds(10)).keep(story, make: { self.draft }, covers: screen.covers)
        XCTAssertEqual(screen.closes, 1)
        XCTAssertEqual(screen.opened.map(\.page.id), [draft.page.id])
        XCTAssertEqual(screen.cover, .draft)
        XCTAssertTrue(screen.discarded.isEmpty)
    }

    /// Closed while the photos were still being saved: the draft is dropped.
    func testStoryClosedWhileMakingOpensNothing() async {
        let story = UUID()
        let screen = Screen()
        screen.cover = .story(story)
        await TriggerKeep(gap: .milliseconds(10)).keep(story, make: {
            screen.cover = nil
            return self.draft
        }, covers: screen.covers)
        XCTAssertTrue(screen.opened.isEmpty, "no editor after the story was closed")
        XCTAssertNil(screen.cover)
        XCTAssertEqual(screen.discarded.map(\.page.id), [draft.page.id])
    }

    /// Closed, then a page opened meanwhile: that page is left alone.
    func testAnotherCoverOpenedWhileMakingIsKept() async {
        let story = UUID()
        let screen = Screen()
        screen.cover = .story(story)
        await TriggerKeep(gap: .milliseconds(10)).keep(story, make: {
            screen.cover = .editor
            return self.draft
        }, covers: screen.covers)
        XCTAssertEqual(screen.closes, 0, "the editor the writer opened is not closed")
        XCTAssertEqual(screen.cover, .editor)
        XCTAssertTrue(screen.opened.isEmpty)
        XCTAssertEqual(screen.discarded.count, 1)
    }

    /// Another story (the same push opened again) is not the one that asked.
    func testAnotherStoryOfTheSamePushIsNotTheOneThatAsked() async {
        let screen = Screen()
        let asked = UUID()
        screen.cover = .story(asked)
        await TriggerKeep(gap: .milliseconds(10)).keep(asked, make: {
            screen.cover = .story(UUID())
            return self.draft
        }, covers: screen.covers)
        XCTAssertEqual(screen.closes, 0)
        XCTAssertTrue(screen.opened.isEmpty)
    }

    /// A cover put up in the swap's pause stays; the draft gives way.
    func testCoverOpenedInTheGapIsKept() async {
        let story = UUID()
        let screen = Screen()
        screen.cover = .story(story)
        let keep = TriggerKeep(gap: .milliseconds(300))
        let task = Task { await keep.keep(story, make: { self.draft }, covers: screen.covers) }
        while screen.closes == 0 { await Task.yield() }
        screen.cover = .editor
        await task.value
        XCTAssertEqual(screen.cover, .editor)
        XCTAssertTrue(screen.opened.isEmpty)
        XCTAssertEqual(screen.discarded.count, 1)
    }

    /// From the story's close to the draft's open no push may open: Home
    /// is bare for that pause, and a push opened in it would be swapped
    /// away by the draft.
    func testNoPushOpensWhileSwitching() async {
        let story = UUID()
        let screen = Screen()
        screen.cover = .story(story)
        let keep = TriggerKeep(gap: .milliseconds(300))
        XCTAssertTrue(keep.mayOpenPush(coverUp: false))
        let task = Task { await keep.keep(story, make: { self.draft }, covers: screen.covers) }
        while screen.closes == 0 { await Task.yield() }
        XCTAssertNil(screen.cover, "Home is bare in the pause")
        XCTAssertFalse(keep.mayOpenPush(coverUp: false), "a pending push waits")
        await task.value
        XCTAssertFalse(keep.mayOpenPush(coverUp: true), "the draft is the cover now")
        XCTAssertTrue(keep.mayOpenPush(coverUp: false))
    }

    func testCoverUpHoldsAPush() {
        XCTAssertFalse(TriggerKeep().mayOpenPush(coverUp: true))
    }
}
