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

    // Expanded text and drafts carry "- " list lines; the screen shows
    // real bullets, not raw markers (issue #28 F4).
    func testListMarkersBecomeBullets() {
        let rendered = ChatMarkdown.attributed("groceries\n- eggs\n- milk\n* bread")
        let characters = String(rendered.characters)
        XCTAssertFalse(characters.contains("- eggs"), "raw dash markers must not reach the screen")
        XCTAssertTrue(characters.contains("\u{2022}  eggs"))
        XCTAssertTrue(characters.contains("\u{2022}  milk"))
        XCTAssertTrue(characters.contains("\u{2022}  bread"), "asterisk markers count too")
    }

    // Indented markers keep their indentation; mid-sentence dashes stay.
    func testBulletSwapIsConservative() {
        XCTAssertEqual(
            ChatMarkdown.withBullets("  - nested\nwell - not a list"),
            "  \u{2022}  nested\nwell - not a list"
        )
    }
}
