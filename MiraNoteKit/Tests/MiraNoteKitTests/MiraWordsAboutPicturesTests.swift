import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraWordsAboutPicturesTests: XCTestCase {
    private func editorWithPhoto() -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addImages(
            [ImageRef(displayName: "sunset", fileName: "p.png")],
            around: CGPoint(x: 150, y: 100))
        return editor
    }

    func testMengsExactPhraseBecomesACaption() {
        // Device repro 2026-07-11: this restyled the photo.
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("Add a text to describe the picture", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testDescribeThePhotoBecomesACaption() {
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("describe the photo", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testChineseDescribeBecomesACaption() {
        let editor = editorWithPhoto()
        // "miaoshu yixia zhaopian" -- describe the photo.
        let intent = MiraIntent.classify(
            "\u{63CF}\u{8FF0}\u{4E00}\u{4E0B}\u{7167}\u{7247}", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testAddAFewWordsAboutThePhotoIsACaption() {
        // Review catch: same bug class, different phrasing -- the guard
        // list and the caption list must be ONE list.
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("add a few words about the photo", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testChineseAddWordsToThePhotoIsACaption() {
        let editor = editorWithPhoto()
        // "gei zhaopian jia yi duan wenzi" -- add a passage to the photo.
        let intent = MiraIntent.classify(
            "\u{7ED9}\u{7167}\u{7247}\u{52A0}\u{4E00}\u{6BB5}\u{6587}\u{5B57}", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testFreeEditStillWorksWithoutWordCues() {
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("make the photo feel like autumn", editor: editor)
        guard case .editPhoto = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
    }

    func testZeroPhotoFilterAskGetsTheHonestQuestion() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("make the photo black and white", editor: editor)
        guard case .clarifyPhoto(let question) = intent else {
            return XCTFail("expected clarifyPhoto, got \(intent)")
        }
        XCTAssertTrue(question.contains("No photo"), "zero photos must not say 'more than one'")
    }
}
