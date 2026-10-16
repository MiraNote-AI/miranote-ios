import XCTest
@testable import MiraNote

/// The chat field sends only on the keyboard's Return key: a new line typed
/// at the end of words, with nothing selected. Pastes, Shift+Return, a
/// keyboard's marked text and dictation insert their new lines instead.
final class ChatReturnTests: XCTestCase {
    private func sends(_ replacement: String, at location: Int, length: Int = 0,
                       in text: String, fromReturnKey: Bool = true) -> Bool {
        ChatReturn.sends(replacing: NSRange(location: location, length: length), with: replacement,
                         in: text, fromReturnKey: fromReturnKey)
    }

    func testTheReturnKeyAtTheEndOfWordsSends() {
        XCTAssertTrue(sends("\n", at: 5, in: "hello"))
    }

    func testANewLineThatIsNotTheReturnKeyDoesNotSend() {
        XCTAssertFalse(sends("\n", at: 5, in: "hello", fromReturnKey: false),
                       "a pasted new line, Shift+Return, marked text or dictation")
    }

    func testReturnInsideTheWordsOrOverASelectionDoesNotSend() {
        XCTAssertFalse(sends("\n", at: 2, in: "hello"), "the cursor is inside the words")
        XCTAssertFalse(sends("\n", at: 3, length: 2, in: "hello"), "it replaces a selection")
    }

    func testReturnInAnEmptyFieldDoesNotSend() {
        XCTAssertFalse(sends("\n", at: 0, in: ""))
        XCTAssertFalse(sends("\n", at: 2, in: "  "), "only spaces")
    }

    func testWordsEndingInANewLineDoNotSend() {
        XCTAssertFalse(sends("more\n", at: 5, in: "hello"))
    }

    func testTheEndCountsInUTF16() {
        let text = "caf\u{E9} \u{2615}"
        XCTAssertTrue(sends("\n", at: (text as NSString).length, in: text))
    }

    // MARK: Shift+Return

    // XCUITest's hardware Return never reaches the text system on an iPhone
    // simulator, so the key command is driven here.

    @MainActor
    func testShiftReturnPutsANewLineInWithoutSending() throws {
        var sent = false
        let field = ChatTextView(text: .constant(""), isFocused: .constant(false),
                                 font: .systemFont(ofSize: 12)) { sent = true }
        let coordinator = field.makeCoordinator()
        let view = ChatInputView()
        view.delegate = coordinator
        view.text = "first line"
        view.selectedRange = NSRange(location: 10, length: 0)

        let command = try XCTUnwrap(view.keyCommands?.first { $0.input == "\r" && $0.modifierFlags == .shift })
        XCTAssertTrue(command.wantsPriorityOverSystemBehavior, "the system's Return must not take it first")
        view.perform(try XCTUnwrap(command.action))
        XCTAssertEqual(view.text, "first line\n")
        XCTAssertFalse(sent)

        // The plain Return key after it still sends.
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 11, length: 0),
                                            replacementText: "\n"))
        XCTAssertTrue(sent)
    }
}
