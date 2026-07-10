import XCTest
@testable import MiraNoteKit

final class ChatMarkdownTests: XCTestCase {
    // The live persona bolds cited page titles; the bubble must render
    // the emphasis, never print the asterisks.
    func testBoldMarkdownRendersWithoutAsterisks() {
        let rendered = ChatMarkdown.attributed(
            "According to **\"Lunch by the river\"**, you noted a calm afternoon."
        )
        let characters = String(rendered.characters)
        XCTAssertFalse(characters.contains("**"), "asterisks must not reach the screen")
        XCTAssertTrue(characters.contains("\"Lunch by the river\""), "the words survive")

        let hasBoldRun = rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        XCTAssertTrue(hasBoldRun, "the emphasis is kept as styling")
    }

    func testPlainTextPassesThroughVerbatim() {
        let plain = "No markdown here, just words."
        XCTAssertEqual(String(ChatMarkdown.attributed(plain).characters), plain)
    }

    // Multi-line replies keep their line breaks (inline-only parsing).
    func testLineBreaksSurvive() {
        let rendered = ChatMarkdown.attributed("first line\nsecond line")
        XCTAssertTrue(String(rendered.characters).contains("first line\nsecond line"))
    }
}
