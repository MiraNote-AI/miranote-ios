import MiraNoteKit
import XCTest

/// iOS-side twin of MiraNoteKit's ChatMarkdownTests emoji case: the
/// simulator's Foundation parses markdown with different code than macOS
/// (where `swift test` runs), and the chat-bubble mojibake reproduced only
/// on device. This one runs on the simulator via `xcodebuild test`.
final class ChatMarkdownRenderingTests: XCTestCase {
    func testEmojiSurvivesMarkdownParsingOnIOS() {
        let samples = [
            "Hi there! \u{1F44B} I can see you have a little welcome page open",
            "tap, drag, tilt, long-press\u{2026} \u{2728}",
            "Want to change something? Just ask. \u{1F60A}",
            "Welcome \u{2014} excited to have you here. \u{1F60A}",
            "**\"A little welcome\"** \u{2014} is a lovely start \u{1F44B}",
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
