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

    // The live persona decorates greetings with emoji (wave, smile) and
    // symbol+VS16 sequences (sun). None of them may corrupt into U+FFFD
    // or lose their variation selector on the way through the parser.
    func testEmojiAndVariationSelectorsSurviveMarkdownParsing() {
        let samples = [
            "Hi! \u{1F44B} How can I help?",
            "hey \u{1F60A} not bad!",
            "Good morning! \u{2600}\u{FE0F} Ready when you are.",
            "**Bold** with a wave \u{1F44B} and sun \u{2600}\u{FE0F} together.",
            "\u{1F44B} leading emoji, **then** markdown",
        ]
        for sample in samples {
            let rendered = String(ChatMarkdown.attributed(sample).characters)
            XCTAssertFalse(
                rendered.unicodeScalars.contains("\u{FFFD}"),
                "replacement character leaked for: \(sample)"
            )
            for scalar in sample.unicodeScalars where scalar.value > 0x7F {
                XCTAssertTrue(
                    rendered.unicodeScalars.contains(scalar),
                    "lost U+\(String(scalar.value, radix: 16)) in: \(sample)"
                )
            }
        }
    }
}
