import XCTest
@testable import MiraNoteKit

/// The chat box's Go while writing (#205 F6B): the typed words pick the
/// transform they name, read as the chat reads them, and a polish otherwise.
@MainActor
final class TextRewriteAskTests: XCTestCase {
    private let coordinator = MiraCanvasCoordinator(
        text: ScriptedText(), chat: ScriptedChat(), workingDelay: .milliseconds(1), timeout: .seconds(5)
    )

    func testTheWordsPickTheTransformTheyName() async throws {
        let asks: [(String, TextTransformMode)] = [
            ("make it warmer", .polish), ("Expand this", .expand), ("a bit shorter", .shorten),
            ("tighten it up", .clean)
        ]
        for (words, mode) in asks {
            let rewritten = try await coordinator.rewriteText("we walked", asked: words)
            XCTAssertEqual(rewritten, "[\(mode.rawValue)] we walked", words)
        }
    }

    func testOtherWordsPolish() async throws {
        let rewritten = try await coordinator.rewriteText("we walked", asked: "more formal please")
        XCTAssertEqual(rewritten, "[polish] we walked")
    }

    func testAFailureReachesTheCaller() async {
        let failing = MiraCanvasCoordinator(
            text: ScriptedText(error: URLError(.notConnectedToInternet)), chat: ScriptedChat(),
            workingDelay: .milliseconds(1), timeout: .seconds(5)
        )
        do {
            _ = try await failing.rewriteText("we walked", asked: "make it warmer")
            XCTFail("the failure is thrown, for the caption")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }
}
