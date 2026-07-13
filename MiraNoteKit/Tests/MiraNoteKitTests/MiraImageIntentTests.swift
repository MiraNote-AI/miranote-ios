import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraImageIntentTests: XCTestCase {
    private func editorWithPhotos(_ count: Int, selectFirst: Bool = false) -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        var first: CanvasItem.ID?
        for index in 0..<count {
            let ids = editor.addImages(
                [ImageRef(displayName: "photo \(index)", fileName: "f\(index).png")],
                around: CGPoint(x: 150, y: 100 + CGFloat(index) * 200)
            )
            if index == 0 { first = ids.first }
        }
        if selectFirst, let first { editor.select(first) }
        return editor
    }

    func testDrawClassifiesAsGeneration() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage(let prompt, let sticker) = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("paper crane"))
        XCTAssertFalse(sticker)
    }

    func testStickerCueGeneratesStickerKind() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify(
            "\u{6765}\u{4E00}\u{5F20}\u{5496}\u{5561}\u{676F}\u{8D34}\u{7EB8}",
            editor: editor
        )
        guard case .generateImage(_, let sticker) = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
        XCTAssertTrue(sticker)
    }

    func testPhotoWarmerIsTheFilterNotPolish() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("make the photo warmer", editor: editor)
        guard case .applyFilter(_, let name) = intent else {
            return XCTFail("expected applyFilter, got \(intent)")
        }
        XCTAssertEqual(name, "warm")
    }

    func testPlainWarmerStaysPolish() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("hello words on the page", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify("make it warmer", editor: editor)
        guard case .transformText = intent else {
            return XCTFail("expected transformText, got \(intent)")
        }
    }

    func testShortenRoutesToShortenNotClean() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("a rather long note about the afternoon", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify("shorten the text", editor: editor)
        guard case .transformText(_, _, .shorten) = intent else {
            return XCTFail("expected transformText(.shorten), got \(intent)")
        }
    }

    func testCleanUpRoutesToClean() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("messy words all over", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify("clean up the text", editor: editor)
        guard case .transformText(_, _, .clean) = intent else {
            return XCTFail("expected transformText(.clean), got \(intent)")
        }
    }

    func testAmbiguousPhotoAsksToTap() {
        let editor = editorWithPhotos(2)
        let intent = MiraIntent.classify("make the photo black and white", editor: editor)
        guard case .clarifyPhoto(let question) = intent else {
            return XCTFail("expected clarifyPhoto, got \(intent)")
        }
        XCTAssertTrue(question.contains("tap the one you mean"))
    }

    func testSelectedPhotoWinsWhenSeveral() {
        let editor = editorWithPhotos(2, selectFirst: true)
        let intent = MiraIntent.classify(
            "\u{628A}\u{7167}\u{7247}\u{9ED1}\u{767D}", editor: editor
        )
        guard case .applyFilter(_, let name) = intent else {
            return XCTFail("expected applyFilter, got \(intent)")
        }
        XCTAssertEqual(name, "bw")
    }

    func testPolaroidFrameCue() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("give the photo a polaroid frame", editor: editor)
        guard case .applyFrame(_, let name) = intent else {
            return XCTFail("expected applyFrame, got \(intent)")
        }
        XCTAssertEqual(name, "polaroid")
    }

    func testStickerCutoutOnThePhoto() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("turn the photo into a sticker", editor: editor)
        guard case .makeSticker = intent else {
            return XCTFail("expected makeSticker, got \(intent)")
        }
    }

    func testFreeFormPhotoAskBecomesStylize() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("make the photo feel like autumn", editor: editor)
        guard case .editPhoto(_, _, let instruction) = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
        XCTAssertTrue(instruction.contains("autumn"))
    }

    func testChangeThePhotoIsAFreeEdit() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("change the photo to feel like winter", editor: editor)
        guard case .editPhoto(_, _, let instruction) = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
        XCTAssertTrue(instruction.contains("winter"))
    }

    func testBiggerTargetsTheTextBlock() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("hello words", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify("make it bigger", editor: editor)
        guard case .resizeText(let target, let up) = intent else {
            return XCTFail("expected resizeText, got \(intent)")
        }
        XCTAssertEqual(target, id)
        XCTAssertTrue(up)
    }

    func testGreenRecolorsToForest() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("hello words", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify(
            "\u{6362}\u{6210}\u{7EFF}\u{8272}", editor: editor
        )
        guard case .recolorText(_, let color) = intent else {
            return XCTFail("expected recolorText, got \(intent)")
        }
        XCTAssertEqual(color, "forest")
    }

    func testNoCueStillConverses() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("how was my week", editor: editor)
        guard case .converse = intent else {
            return XCTFail("expected converse, got \(intent)")
        }
    }
}
