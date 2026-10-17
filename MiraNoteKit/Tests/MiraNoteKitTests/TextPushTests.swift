import Foundation
import XCTest
@testable import MiraNoteKit

/// What a text box's growth pushed is the box's to take back -- and only
/// that: a shrink takes back what it pushed (no ratchet), Cancel and a
/// committed preview put back only the session's own pushes, never what
/// other actions moved meanwhile.
@MainActor
final class TextPushTests: XCTestCase {
    private func top(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) - (item?.size.height ?? 0) / 2 }
    private func bottom(_ item: CanvasItem?) -> CGFloat { (item?.position.y ?? 0) + (item?.size.height ?? 0) / 2 }

    /// A 60 pt block (top 40) with a photo 20 below it (top 120).
    private func blockOverPhoto() -> (CanvasItem, CanvasItem) {
        let block = CanvasItem(content: .text(TextBlock(text: "lunch by the river")),
                               position: CGPoint(x: 150, y: 70), size: CGSize(width: 240, height: 60))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 150, y: 220),
                               size: CGSize(width: 240, height: 200), zIndex: 1)
        return (block, photo)
    }

    /// The page as `landTitle` leaves it when the title needs room: a title
    /// on top, everything else slid down by `slide`.
    private func landTitle(on editor: CanvasViewModel, slide: CGFloat) -> CanvasItem.ID {
        let existing = editor.items.map(\.id)
        let title = editor.addText("A soft title", at: CGPoint(x: 150, y: 66), pointSize: 30,
                                   size: CGSize(width: 270, height: 60))
        for id in existing {
            editor.slide(itemID: id, by: slide)
        }
        return title
    }

    // MARK: Cancel

    /// Mira's title lands while the user writes and slides the page down:
    /// Cancel puts the block's words back, where the title put the block.
    func testCancelKeepsTheBlockWhereATitleLandingMovedIt() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "lunch by the river, then a long walk home")
        let title = landTitle(on: editor, slide: 100)

        editor.cancelEditingText()
        guard case .text(let words) = editor.item(block.id)?.content else { return XCTFail("block gone") }
        XCTAssertEqual(words.text, "lunch by the river")
        XCTAssertEqual(top(editor.item(block.id)), 140, accuracy: 0.5, "the block jumped back onto the title")
        XCTAssertGreaterThanOrEqual(top(editor.item(block.id)), bottom(editor.item(title)) - 0.5)
        XCTAssertEqual(top(editor.item(photo.id)), 220, accuracy: 0.5, "the photo stays where the title put it")
    }

    /// The same with growth: the session's own push is taken back, the
    /// slide the title made is not.
    func testCancelTakesBackOnlyTheSessionsOwnPush() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "lunch by the river, then a long walk home")
        editor.autosizeTextHeight(itemID: block.id, to: 90)
        XCTAssertEqual(top(editor.item(photo.id)), 150, accuracy: 0.5, "pushed by the 30 pt growth")
        _ = landTitle(on: editor, slide: 100)

        editor.cancelEditingText()
        XCTAssertEqual(top(editor.item(block.id)), 140, accuracy: 0.5)
        XCTAssertEqual(editor.item(block.id)?.size.height ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(top(editor.item(photo.id)), 220, accuracy: 0.5,
                       "the push goes back, the title's slide stays")
    }

    /// An element moved while the user writes (a drag that landed in the
    /// session) stays where it was moved.
    func testCancelLeavesAnElementMovedDuringTheSession() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "more words")
        editor.beginChange()
        editor.move(itemID: photo.id, to: CGPoint(x: 150, y: 600))

        editor.cancelEditingText()
        XCTAssertEqual(editor.item(photo.id)?.position.y ?? 0, 600, accuracy: 0.5)
        editor.undo()
        XCTAssertEqual(editor.item(photo.id)?.position.y ?? 0, 220, accuracy: 0.5, "the move is its own step")
    }

    /// A new block that grew over the photo, then Cancel: the block goes,
    /// and so does its push.
    func testCancelOnANewBlockTakesItsPushBack() {
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 150, y: 220),
                               size: CGSize(width: 240, height: 200))
        let editor = CanvasViewModel(memory: Memory(items: [photo]))
        let id = editor.addText("", at: CGPoint(x: 150, y: 70), size: CGSize(width: 240, height: 60))
        editor.startEditingText(id, recordingUndo: false)
        editor.setText(itemID: id, to: "a long new paragraph")
        editor.autosizeTextHeight(itemID: id, to: 100)
        XCTAssertEqual(top(editor.item(photo.id)), 160, accuracy: 0.5)

        editor.cancelEditingText()
        XCTAssertNil(editor.item(id))
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position)
    }

    // MARK: Previews

    /// A rewrite preview grows the block; a title lands meanwhile; the
    /// commit's undo takes the rewrite back -- not the title's slide.
    func testUndoOfACommittedPreviewKeepsWhatOtherActionsMoved() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        let original = editor.item(block.id)!
        editor.setText(itemID: block.id, to: "a much longer rewritten paragraph about the river")
        editor.autosizeTextHeight(itemID: block.id, to: 90)
        let title = landTitle(on: editor, slide: 100)
        editor.commitPreview(of: original)

        editor.undo()
        guard case .text(let words) = editor.item(block.id)?.content else { return XCTFail("block gone") }
        XCTAssertEqual(words.text, "lunch by the river")
        XCTAssertGreaterThanOrEqual(top(editor.item(block.id)), bottom(editor.item(title)) - 0.5,
                                    "the block went back onto the title")
        XCTAssertEqual(top(editor.item(photo.id)), 220, accuracy: 0.5)
    }

    /// Harness seed 104372539625494: the AI row open, a longer version
    /// shown (it pushes the photo), then Cancel -- which drops the preview
    /// first. The photo comes back up with the block.
    func testCancelWithALongerRewriteShownPutsThePhotoBack() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        let original = editor.item(block.id)!
        editor.setText(itemID: block.id, to: "a much longer rewritten paragraph about the river")
        editor.autosizeTextHeight(itemID: block.id, to: 110)
        XCTAssertEqual(top(editor.item(photo.id)), 170, accuracy: 0.5, "pushed by the 50 pt growth")

        editor.discardPreview(of: original)
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position, "the preview's push stayed")
        editor.cancelEditingText()
        XCTAssertEqual(editor.items, [block, photo])
    }

    // MARK: No ratchet

    /// Meng's probe: a 60 pt block over a photo fitted to 40 and back to 60
    /// leaves the photo where it was.
    func testAShrinkThenTheSameGrowthLeavesThePhoto() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 40 : nil }
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position)
    }

    /// Outside any session: a growth pushes, the shrink back takes it back.
    func testAShrinkTakesBackWhatTheBoxPushedEarlier() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 86 : nil }
        XCTAssertEqual(top(editor.item(photo.id)), 146, accuracy: 0.5)
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position)
        XCTAssertEqual(editor.item(block.id), block, "nothing left to remember")
    }

    /// The curated sets toggled back and forth (each re-fits every block):
    /// after N rounds every element is where it started -- also when the
    /// page is saved and opened again between rounds.
    func testTogglingHeightsBackAndForthLeavesEveryElementWhereItStarted() throws {
        let (block, photo) = blockOverPhoto()
        let sticker = CanvasItem(content: .sticker(GeneratedSticker(prompt: "s", symbolName: "sun.max")),
                                 position: CGPoint(x: 150, y: 400), size: CGSize(width: 80, height: 80), zIndex: 2)
        var editor = CanvasViewModel(memory: Memory(items: [block, photo, sticker]))
        for round in 0..<4 {
            editor.fitTextHeights { $0.id == block.id ? 72 : nil }
            editor.fitTextHeights { $0.id == block.id ? 50 : nil }
            editor.fitTextHeights { $0.id == block.id ? 60 : nil }
            let saved = try JSONEncoder().encode(editor.memory)
            editor = CanvasViewModel(memory: try JSONDecoder().decode(Memory.self, from: saved))
            XCTAssertEqual(editor.item(photo.id)?.position, photo.position, "round \(round)")
            XCTAssertEqual(editor.item(sticker.id)?.position, sticker.position, "round \(round)")
        }
    }

    /// In a writing session too: a line typed and deleted N times.
    func testTypingAndDeletingALineRepeatedlyPushesNoFurther() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        for _ in 0..<3 {
            editor.autosizeTextHeight(itemID: block.id, to: 84)
            XCTAssertEqual(top(editor.item(photo.id)), 144, accuracy: 0.5)
            editor.autosizeTextHeight(itemID: block.id, to: 40)
            XCTAssertEqual(editor.item(photo.id)?.position, photo.position)
        }
        editor.endEditingText()
    }

    /// A shrink never pulls up what it did not push: a photo the box never
    /// pushed stays put.
    func testAShrinkPullsNothingItDidNotPush() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 30 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position)
    }

    /// Room a shrink left below a box is not room forever: a photo moved
    /// up against the shrunk box is pushed when the box grows again.
    func testAPhotoMovedIntoTheRoomAShrinkLeftIsPushedAgain() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 40 : nil }
        editor.beginChange()
        editor.move(itemID: photo.id, to: CGPoint(x: 150, y: 80 + 100))
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertGreaterThanOrEqual(top(editor.item(photo.id)), bottom(editor.item(block.id)) - 0.5,
                                    "the grown words run under the photo")
    }

    /// Tidy lays the page out anew: a push from before it is not taken
    /// back later, which would bunch the tidy column up.
    func testTidyForgetsEarlierPushes() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 100 : nil }
        editor.quickOrganize(canvasWidth: 390)
        let tidy = editor.item(photo.id)?.position
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position, tidy)
    }

    // MARK: A placed element stays put

    /// Harness seed 104375194061263: a growth pushes the photo, the user
    /// drags the photo somewhere else below the block, the block shrinks:
    /// the photo stays where the user put it -- and growing back to the
    /// old height does not push it either.
    func testAShrinkNeverLiftsAPhotoTheUserDraggedAfterThePush() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        XCTAssertEqual(top(editor.item(photo.id)), 150, accuracy: 0.5)
        editor.beginChange()
        editor.move(itemID: photo.id, to: CGPoint(x: 150, y: 400))

        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position.y ?? 0, 400, accuracy: 0.5, "the shrink pulled the dragged photo")
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position.y ?? 0, 400, accuracy: 0.5, "growing back pushed it")
    }

    /// A photo added under a block after the block's push was never pushed
    /// by it: the block's shrink leaves it where it was added.
    func testAShrinkNeverLiftsAPhotoAddedAfterThePush() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        let added = editor.addImages([ImageRef(displayName: "q")], around: CGPoint(x: 150, y: 600)).first!
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(editor.item(photo.id)?.position, photo.position, "what it pushed comes back")
        XCTAssertEqual(editor.item(added)?.position.y ?? 0, 600, accuracy: 0.5, "what it never pushed stays")
    }

    /// Cancel takes back the session's push from what it pushed, but not
    /// from an element the user dragged during the session.
    func testCancelLeavesAPhotoDraggedAfterTheSessionPushedIt() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "lunch by the river, then a long walk home")
        editor.autosizeTextHeight(itemID: block.id, to: 90)
        editor.beginChange()
        editor.move(itemID: photo.id, to: CGPoint(x: 150, y: 500))

        editor.cancelEditingText()
        XCTAssertEqual(editor.item(photo.id)?.position.y ?? 0, 500, accuracy: 0.5)
    }

    // MARK: Reversible fits (harness ratchets)

    private func text(_ x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CanvasItem {
        CanvasItem(content: .text(TextBlock(text: "words")), position: CGPoint(x: x, y: top + height / 2),
                   size: CGSize(width: width, height: height))
    }

    private func photo(_ x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CanvasItem {
        CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: x, y: top + height / 2),
                   size: CGSize(width: width, height: height))
    }

    /// Harness seed 104523842464327 (curated sets 3, 6, 3, ...): a box grows
    /// while the box right under it shrinks. What is below follows the box
    /// right above it -- before, it took the far box's push and sank 34 pt
    /// a round.
    func testAStackOfBoxesSizedBackAndForthLeavesWhatIsBelow() {
        let upper = text(150, top: 40, width: 240, height: 60)
        let lower = text(150, top: 120, width: 240, height: 60)
        let below = photo(150, top: 200, width: 240, height: 100)
        let editor = CanvasViewModel(memory: Memory(items: [upper, lower, below]))
        let first: [CanvasItem.ID: CGFloat] = [upper.id: 60, lower.id: 100]
        let second: [CanvasItem.ID: CGFloat] = [upper.id: 80, lower.id: 60]
        editor.fitTextHeights { first[$0.id] }
        let start = editor.item(below.id)?.position
        let gap = top(editor.item(below.id)) - bottom(editor.item(lower.id))
        for round in 0..<3 {
            editor.fitTextHeights { second[$0.id] }
            XCTAssertEqual(top(editor.item(below.id)) - bottom(editor.item(lower.id)), gap, accuracy: 0.5,
                           "round \(round): the photo follows the box right above it, not the far one")
            editor.fitTextHeights { first[$0.id] }
            XCTAssertEqual(editor.item(below.id)?.position, start, "round \(round)")
        }
    }

    /// Harness seed 104701689660850: two elements right above a photo move
    /// opposite ways (a box grows, a photo under a shrinking box is pulled
    /// up). Reversed, the photo comes back -- before, "a push wins" pushed
    /// it every round.
    func testOppositeMovesRightAboveReverseExactly() {
        let leftBox = text(80, top: 40, width: 140, height: 60)
        let leftPhoto = photo(80, top: 120, width: 140, height: 80)
        let rightBox = text(300, top: 40, width: 160, height: 60)
        let wide = photo(190, top: 260, width: 340, height: 80)
        let editor = CanvasViewModel(memory: Memory(items: [leftBox, leftPhoto, rightBox, wide]))
        let first: [CanvasItem.ID: CGFloat] = [leftBox.id: 100, rightBox.id: 60]
        let second: [CanvasItem.ID: CGFloat] = [leftBox.id: 60, rightBox.id: 100]
        editor.fitTextHeights { first[$0.id] }
        let start = editor.items
        for round in 0..<3 {
            editor.fitTextHeights { second[$0.id] }
            editor.fitTextHeights { first[$0.id] }
            XCTAssertEqual(editor.items.map(\.position), start.map(\.position), "round \(round)")
        }
    }

    /// Harness seed 104956515494674: a pull held back (a sticker dragged
    /// after the push stays put) is room the next push uses first, so the
    /// box shrunk and grown back leaves the sticker, and what is under it.
    func testAPullHeldBackIsUsedByTheNextPush() {
        let block = text(150, top: 40, width: 240, height: 60)
        let sticker = photo(80, top: 120, width: 100, height: 60)
        let under = photo(150, top: 180, width: 240, height: 100)
        let editor = CanvasViewModel(memory: Memory(items: [block, sticker, under]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        editor.beginChange()
        editor.move(itemID: sticker.id, to: editor.item(sticker.id)!.position)
        let placed = [editor.item(sticker.id)?.position, editor.item(under.id)?.position]
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual([editor.item(sticker.id)?.position, editor.item(under.id)?.position], placed,
                       "the dragged sticker stays, and so does what is under it")
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        XCTAssertEqual([editor.item(sticker.id)?.position, editor.item(under.id)?.position], placed,
                       "growing back pushes nothing it never pulled")
    }

    /// Harness seed 105521910313471: words erased, a sticker dragged into
    /// the room the shrink left, Cancel. The block grows back to its height
    /// and the sticker is pushed clear of it, not run into.
    func testCancelPushesClearWhatWasDraggedIntoTheRoom() {
        let block = text(150, top: 40, width: 240, height: 96)
        let editor = CanvasViewModel(memory: Memory(items: [block]))
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "w")
        editor.autosizeTextHeight(itemID: block.id, to: 36)
        let sticker = editor.addSticker(GeneratedSticker(prompt: "s", symbolName: "sun.max"),
                                        at: CGPoint(x: 150, y: 76 + 10 + 44))

        editor.cancelEditingText()
        XCTAssertEqual(editor.item(block.id)?.size.height ?? 0, 96, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(top(editor.item(sticker)), bottom(editor.item(block.id)) - 0.5,
                                    "the block grew back over the sticker")
    }

    /// Harness seed 1837298725893: a block made shorter by hand forgets its
    /// earlier push, so typing and erasing leaves the photo where it is.
    func testABoxSizedByHandStartsItsPushesAfresh() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        editor.beginChange()
        editor.resize(itemID: block.id, to: CGSize(width: 240, height: 60))
        let start = editor.item(photo.id)?.position
        editor.startEditingText(block.id)
        editor.autosizeTextHeight(itemID: block.id, to: 120)
        editor.autosizeTextHeight(itemID: block.id, to: 60)
        XCTAssertEqual(editor.item(photo.id)?.position, start)
    }

    /// Tidy places every element anew: a pull held back before it is not
    /// room a later push may use, or the push would not keep the gap Tidy
    /// laid out. (Mutation check: Tidy keeping the fit offsets survived.)
    func testTidyForgetsHeldBackPulls() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        editor.beginChange()
        editor.move(itemID: photo.id, to: editor.item(photo.id)!.position)
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertGreaterThan(editor.item(photo.id)?.fitOffset?.spared ?? 0, 0, "precondition: a held-back pull")
        editor.quickOrganize(canvasWidth: 390)
        let gap = top(editor.item(photo.id)) - bottom(editor.item(block.id))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        XCTAssertEqual(top(editor.item(photo.id)) - bottom(editor.item(block.id)), gap, accuracy: 0.5,
                       "the growth after Tidy kept Tidy's gap")
    }

    /// An element Mira puts somewhere (a page edit) is placed there: the
    /// box above it shrinking never lifts it. (Mutation check survivor.)
    func testAShrinkNeverLiftsAPhotoMiraPlaced() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 90 : nil }
        XCTAssertTrue(editor.applyPageEdits([ResolvedChange(id: photo.id, y: 400)]))
        editor.fitTextHeights { $0.id == block.id ? 60 : nil }
        XCTAssertEqual(top(editor.item(photo.id)), 400, accuracy: 0.5, "the shrink lifted Mira's placement")
    }

    /// Mira's real title landing slides the page without placing it: the
    /// session's Cancel still takes back its own push from the photo below.
    /// (Mutation check: landTitle moving instead of sliding survived; the
    /// helper above stands in for it elsewhere.)
    func testCancelTakesBackItsPushAfterMirasTitleSlidThePage() {
        let (block, photo) = blockOverPhoto()
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        let mira = MiraCanvasCoordinator(text: ScriptedText(), chat: ScriptedChat())
        editor.startEditingText(block.id)
        editor.setText(itemID: block.id, to: "lunch by the river, then a long walk home")
        editor.autosizeTextHeight(itemID: block.id, to: 90)
        let pushed = top(editor.item(photo.id))
        let blockTop = top(editor.item(block.id))
        mira.landTitle("A soft title", receipt: MiraReceipt(changed: "", kept: ""), editor: editor)
        let slide = top(editor.item(block.id)) - blockTop
        XCTAssertGreaterThan(slide, 0, "precondition: the title slid the page")

        editor.cancelEditingText()
        XCTAssertEqual(top(editor.item(photo.id)), pushed + slide - 30, accuracy: 0.5,
                       "the slide stays, the session's 30 pt push goes")
    }

    /// A pulled element never rises into another element above it.
    func testAPullStopsAtTheElementAbove() {
        let block = CanvasItem(content: .text(TextBlock(text: "b")), position: CGPoint(x: 100, y: 50),
                               size: CGSize(width: 160, height: 40))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 160, y: 200),
                               size: CGSize(width: 240, height: 100))
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.fitTextHeights { $0.id == block.id ? 100 : nil }
        // A sticker beside the block, not under it, placed right over the
        // pushed photo.
        let sticker = editor.addSticker(GeneratedSticker(prompt: "s", symbolName: "sun.max"),
                                        at: CGPoint(x: 260, y: top(editor.item(photo.id)) - 44))
        editor.fitTextHeights { $0.id == block.id ? 40 : nil }
        XCTAssertGreaterThanOrEqual(top(editor.item(photo.id)), bottom(editor.item(sticker)) - 0.5,
                                    "the pulled photo rose into the sticker")
    }
}
