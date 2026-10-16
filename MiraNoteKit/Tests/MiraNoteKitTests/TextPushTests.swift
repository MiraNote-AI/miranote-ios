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
        let existing = editor.items.map { ($0.id, $0.position) }
        let title = editor.addText("A soft title", at: CGPoint(x: 150, y: 66), pointSize: 30,
                                   size: CGSize(width: 270, height: 60))
        for (id, position) in existing {
            editor.move(itemID: id, to: CGPoint(x: position.x, y: position.y + slide))
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
