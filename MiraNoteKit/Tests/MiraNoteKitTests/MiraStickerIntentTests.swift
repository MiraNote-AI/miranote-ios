import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraStickerIntentTests: XCTestCase {
    /// Stickers land first (ids captured per add); optionally one photo
    /// after them, optionally the FIRST sticker selected.
    private func editorWithStickers(
        _ count: Int, selectFirst: Bool = false, addPhoto: Bool = false
    ) -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        var first: CanvasItem.ID?
        for index in 0..<count {
            editor.addSticker(
                GeneratedSticker(prompt: "cat \(index)", symbolName: "sparkles",
                                 fileName: "s\(index).png"),
                at: CGPoint(x: 150, y: 100 + CGFloat(index) * 200)
            )
            if index == 0 { first = editor.items.last?.id }
        }
        if addPhoto {
            _ = editor.addImages(
                [ImageRef(displayName: "photo", fileName: "p.png")],
                around: CGPoint(x: 150, y: 700)
            )
        }
        if selectFirst, let first { editor.select(first) }
        return editor
    }

    func testEnglishEditCueEditsTheOnlySticker() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .editSticker(_, _, let instruction, let prompt) = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
        XCTAssertTrue(instruction.contains("blue"))
        XCTAssertEqual(prompt, "cat 0", "the original label rides along")
    }

    func testChineseEditCueEditsTheOnlySticker() {
        let editor = editorWithStickers(1)
        // "ba tiezhi gaicheng lanse" -- change the sticker to blue.
        let intent = MiraIntent.classify(
            "\u{628A}\u{8D34}\u{7EB8}\u{6539}\u{6210}\u{84DD}\u{8272}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testSelectedStickerWinsWhenSeveral() {
        let editor = editorWithStickers(2, selectFirst: true)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .editSticker(let id, _, _, _) = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
        XCTAssertEqual(id, editor.selectedItemID)
    }

    func testSeveralUnselectedStickersClarify() {
        let editor = editorWithStickers(2)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .clarifySticker(let question) = intent else {
            return XCTFail("expected clarifySticker, got \(intent)")
        }
        XCTAssertTrue(question.contains("tap the one you mean"))
    }

    func testZeroStickersClarify() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .clarifySticker(let question) = intent else {
            return XCTFail("expected clarifySticker, got \(intent)")
        }
        XCTAssertTrue(question.contains("No sticker"))
    }

    func testIndefiniteStickerWishStaysConverse() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("make a sticker of a cat", editor: editor)
        guard case .converse = intent else {
            return XCTFail("expected converse, got \(intent)")
        }
    }

    func testStickerWarmerNeverTouchesThePhoto() {
        let editor = editorWithStickers(1, addPhoto: true)
        let intent = MiraIntent.classify("make the sticker warmer", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testChangeVerbEditsTheSticker() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("change the sticker to blue", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testTurnTheStickerIntoADragonEdits() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("turn the sticker into a dragon", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testAddAHatToTheStickerEdits() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("add a hat to the sticker", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testChineseGaiWithoutBaEdits() {
        let editor = editorWithStickers(1)
        // "tie zhi gai cheng lan se" -- sticker, change to blue (no ba).
        let intent = MiraIntent.classify(
            "\u{8D34}\u{7EB8}\u{6539}\u{6210}\u{84DD}\u{8272}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testChineseGeiAccessoryEdits() {
        let editor = editorWithStickers(1)
        // "gei tie zhi jia ding mao zi" -- give the sticker a hat.
        let intent = MiraIntent.classify(
            "\u{7ED9}\u{8D34}\u{7EB8}\u{52A0}\u{9876}\u{5E3D}\u{5B50}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testAddAStickerOfACatStaysConverse() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("add a sticker of a cat", editor: editor)
        guard case .converse = intent else {
            return XCTFail("expected converse, got \(intent)")
        }
    }

    func testPhotoLikeTheStickerStaysAPhotoEdit() {
        let editor = editorWithStickers(1, addPhoto: true)
        let intent = MiraIntent.classify("make the photo look like the sticker", editor: editor)
        guard case .editPhoto = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
    }

    func testChineseTurnPhotoIntoStickerTargetsThePhoto() {
        let editor = editorWithStickers(0, addPhoto: true)
        // "ba zhaopian biancheng tiezhi" -- turn the photo into a sticker
        // (the soft phrasing, without the cutout verb).
        let intent = MiraIntent.classify(
            "\u{628A}\u{7167}\u{7247}\u{53D8}\u{6210}\u{8D34}\u{7EB8}", editor: editor)
        guard case .editPhoto = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
    }

    func testPhotoCutoutPhraseStillConvertsThePhoto() {
        let editor = editorWithStickers(1, addPhoto: true)
        // "ba zhaopian koucheng tiezhi" -- cut the photo into a sticker.
        let intent = MiraIntent.classify(
            "\u{628A}\u{7167}\u{7247}\u{62A0}\u{6210}\u{8D34}\u{7EB8}", editor: editor)
        guard case .makeSticker = intent else {
            return XCTFail("expected makeSticker, got \(intent)")
        }
    }
}
