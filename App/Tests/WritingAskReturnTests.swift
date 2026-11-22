import XCTest
@testable import MiraNote

/// The writing chat box's Go key against a paste (#236): the key's line
/// break sends, alone or with the last word before it changed in the same
/// change (an autocorrection taken, its last letters landing with the key);
/// a paste's line breaks never do.
final class WritingAskReturnTests: XCTestCase {
    private func goKey(_ words: String, after before: String) -> String? {
        WritingAskReturn.goKey(words, before: before)
    }

    func testTheGoKeyAloneSends() {
        XCTAssertEqual(goKey("make it warmer\n", after: "make it warmer"), "make it warmer")
        XCTAssertEqual(goKey("make it\n warmer", after: "make it warmer"), "make it warmer", "the caret inside")
        XCTAssertEqual(goKey("make it warmer \n", after: "make it warmer "), "make it warmer ")
    }

    func testTheGoKeyWithAnAutocorrectionInTheSameChangeSends() {
        XCTAssertEqual(goKey("make it warmer because\n", after: "make it warmer becuase"), "make it warmer because")
        XCTAssertEqual(goKey("make the\n warmer", after: "make teh warmer"), "make the warmer", "the caret inside")
        XCTAssertEqual(goKey("make it a lot\n", after: "make it alot"), "make it a lot", "into two words")
    }

    func testTheGoKeyWithTheLastLettersInTheSameChangeSends() {
        XCTAssertEqual(goKey("make it warmer\n", after: "make it war"), "make it warmer")
        XCTAssertEqual(goKey("make it warmer\n", after: "mak"), "make it warmer")
    }

    func testAPastedTwoLineAskIsNotTheGoKey() {
        XCTAssertNil(goKey("make it warmer\nand shorter", after: ""))
        XCTAssertNil(goKey("we make it warmer\nand shorter", after: "we "))
        XCTAssertNil(goKey("polish the text\nand make it warmer\n", after: ""), "two line breaks")
    }

    func testAPastedLineEndingInALineBreakIsNotTheGoKey() {
        XCTAssertNil(goKey("polish the text\n", after: ""), "into an empty box")
        XCTAssertNil(goKey("make it polish the text\n", after: "make it "), "after a space")
    }

    func testAChangeBeforeTheLastWordIsNotTheGoKey() {
        XCTAssertNil(goKey("make the warmer\n", after: "make teh warmer"))
    }
}
