import XCTest
@testable import MiraNote

/// The chat field's keyboard Send key sends, wherever the caret is; line
/// breaks come only from Shift+Return or a paste (and a keyboard's marked
/// text and dictation insert theirs).
final class ChatReturnTests: XCTestCase {
    private func sends(_ replacement: String, fromReturnKey: Bool = true) -> Bool {
        ChatReturn.sends(replacement, fromReturnKey: fromReturnKey)
    }

    func testTheReturnKeySends() {
        XCTAssertTrue(sends("\n"))
    }

    func testANewLineThatIsNotTheReturnKeyDoesNotSend() {
        XCTAssertFalse(sends("\n", fromReturnKey: false),
                       "a pasted new line, Shift+Return, marked text or dictation")
    }

    /// The caret inside the words (a word tapped to fix it), or words
    /// selected: the Send key still sends, and nothing is put in or
    /// replaced.
    @MainActor
    func testTheReturnKeyInsideTheWordsOrOverASelectionSendsAndChangesNothing() {
        var sent = 0
        let field = ChatTextView(text: .constant("hello"), isFocused: .constant(false),
                                 font: .systemFont(ofSize: 12)) { sent += 1 }
        let coordinator = field.makeCoordinator()
        let view = ChatInputView()
        view.delegate = coordinator
        view.text = "hello"
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0),
                                            replacementText: "\n"), "a line break went in at the start")
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 1, length: 3),
                                            replacementText: "\n"), "the selected words were replaced")
        XCTAssertEqual(sent, 2)
    }

    @MainActor
    func testTheReturnKeyInAnEmptyFieldSendsAndPutsNoNewLineIn() {
        var sent = false
        let field = ChatTextView(text: .constant(""), isFocused: .constant(false),
                                 font: .systemFont(ofSize: 12)) { sent = true }
        let coordinator = field.makeCoordinator()
        let view = ChatInputView()
        view.delegate = coordinator
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0),
                                            replacementText: "\n"), "the new line is not put in")
        XCTAssertTrue(sent, "a staged photo can go out with the Return key")
    }

    func testWordsEndingInANewLineDoNotSend() {
        XCTAssertFalse(sends("more\n"))
    }

    // MARK: Paste

    /// A paste with nothing to put in makes no change, so nothing would
    /// take its mark: the next Return key would then put a new line in
    /// instead of sending.
    @MainActor
    func testAPasteThatPutsNothingInLeavesTheReturnKeyAlone() {
        var sent = false
        let field = ChatTextView(text: .constant(""), isFocused: .constant(false),
                                 font: .systemFont(ofSize: 12)) { sent = true }
        let coordinator = field.makeCoordinator()
        let view = ChatInputView()
        view.delegate = coordinator
        view.text = "hello"
        view.selectedRange = NSRange(location: 5, length: 0)
        UIPasteboard.general.items = []
        view.paste(nil)
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 5, length: 0),
                                            replacementText: "\n"))
        XCTAssertTrue(sent, "the Return key after an empty paste sends")
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
