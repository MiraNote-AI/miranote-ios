import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraIllustrateTextTests: XCTestCase {
    private func editorWithText(_ words: String = "a quiet morning by the sea") -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText(words, at: CGPoint(x: 150, y: 80))
        return editor
    }

    func testTurnThisTextIntoAPictureCarriesTheWords() {
        let editor = editorWithText()
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("a quiet morning by the sea"),
                      "the page's words ride the prompt, not the instruction")
    }

    func testChineseIntoPictureCarriesTheWords() {
        let editor = editorWithText()
        // "ba zhe duan wenzi hua cheng tu" -- draw this text as a picture.
        let intent = MiraIntent.classify(
            "\u{628A}\u{8FD9}\u{6BB5}\u{6587}\u{5B57}\u{753B}\u{6210}\u{56FE}", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("a quiet morning by the sea"))
    }

    func testAddAPictureBasedOnTheTextIllustrates() {
        // Device repro 2026-07-11 (second round): this hit the photo
        // family's zero-photo clarify instead of illustrating.
        let editor = editorWithText("today I visited Disney and took a picture with Mickey Mouse.")
        let intent = MiraIntent.classify("Add a picture based on the text", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("Disney"))
    }

    func testChinesePeiTuIllustrates() {
        let editor = editorWithText()
        // "gei zhe duan wenzi pei yi zhang tu" -- give this text a picture.
        let intent = MiraIntent.classify(
            "\u{7ED9}\u{8FD9}\u{6BB5}\u{6587}\u{5B57}\u{914D}\u{4E00}\u{5F20}\u{56FE}",
            editor: editor)
        guard case .illustrateText = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
    }

    func testNoTextClarifies() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .clarifyNoText = intent else {
            return XCTFail("expected clarifyNoText, got \(intent)")
        }
    }

    func testSelectedBlockWinsOverLongest() {
        let editor = editorWithText("the much much much longer block of words here")
        let short = editor.addText("tiny sea", at: CGPoint(x: 150, y: 260))
        editor.select(short)
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("tiny sea"))
        XCTAssertFalse(prompt.contains("longer block"))
    }

    func testPerformYieldsPictureChoicesViaArt() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.illustrateText(prompt: "An illustration of: tiny sea")
        let outcome = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        let kinds = await studio.kinds
        XCTAssertEqual(kinds, [.art])
        guard case .imageChoices(let images, _, let placement) = outcome else {
            return XCTFail("expected imageChoices, got \(outcome)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .picture)
    }

    func testPlainDrawIsUntouched() {
        let editor = editorWithText()
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
    }
}
