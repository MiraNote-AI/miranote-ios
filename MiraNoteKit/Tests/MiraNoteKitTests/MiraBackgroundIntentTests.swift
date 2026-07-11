import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraBackgroundIntentTests: XCTestCase {
    func testEnglishBackgroundAskSets() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("give this page a sunset background", editor: editor)
        guard case .setBackground(let prompt) = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("sunset"))
    }

    func testDrawWordStillGoesToBackgroundWhenMentioned() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a starry background", editor: editor)
        guard case .setBackground = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
    }

    func testChineseBackgroundAskSets() {
        let editor = CanvasViewModel(memory: Memory())
        // "huan ge xingkong beijing" -- switch to a starry background.
        let intent = MiraIntent.classify(
            "\u{6362}\u{4E2A}\u{661F}\u{7A7A}\u{80CC}\u{666F}", editor: editor)
        guard case .setBackground = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
    }

    func testRemoveBackgroundClears() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        let intent = MiraIntent.classify("remove the background", editor: editor)
        guard case .clearBackground = intent else {
            return XCTFail("expected clearBackground, got \(intent)")
        }
    }

    func testChineseClearAsk() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        // "qu diao beijing" -- remove the background.
        let intent = MiraIntent.classify("\u{53BB}\u{6389}\u{80CC}\u{666F}", editor: editor)
        guard case .clearBackground = intent else {
            return XCTFail("expected clearBackground, got \(intent)")
        }
    }

    func testPhotoBackgroundAskStaysOutOfTheFamily() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addImages(
            [ImageRef(displayName: "p", fileName: "p.png")],
            around: CGPoint(x: 150, y: 100))
        let intent = MiraIntent.classify("remove the background of the photo", editor: editor)
        if case .setBackground = intent { XCTFail("photo asks must not set the page background") }
        if case .clearBackground = intent { XCTFail("photo asks must not clear the page background") }
    }

    func testStickerMentionStaysOut() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("give the sticker a new background", editor: editor)
        if case .setBackground = intent { XCTFail("sticker asks must not set the page background") }
    }

    func testPlainDrawStillGenerates() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
    }
}
