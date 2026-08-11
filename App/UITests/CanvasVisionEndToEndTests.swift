import XCTest

/// The whole feature, as a person would use it: start a page, put a real
/// photo and real words on it, then ask Mira for the things this work
/// exists to make possible -- against live backends.
///
/// Skipped unless MIRANOTE_LIVE_SEAM=1, because it needs :8002 and :8003
/// running and spends real model calls.
final class CanvasVisionEndToEndTests: XCTestCase {
    private var app: XCUIApplication!

    /// Every ask runs inside the 60s turn budget; give the receipt a
    /// little more than that so a timeout reads as a timeout.
    private let turnWait: TimeInterval = 70

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MIRANOTE_LIVE_SEAM"] == "1",
            "needs live backends; set TEST_RUNNER_MIRANOTE_LIVE_SEAM=1"
        )
        continueAfterFailure = true
        app = XCUIApplication()
        // Samples give a real photo with real pixels. Deliberately NOT
        // -UITEST, which would swap in the offline mocks and prove
        // nothing about the backends.
        app.launchArguments += ["-DEMO-SAMPLES"]
        app.launch()
    }

    /// Type into the canvas ask bar and wait for the turn to settle.
    @discardableResult
    private func ask(_ words: String, expectReceipt: Bool = true) -> String? {
        let input = app.textFields["mira.input"]
        guard input.waitForExistence(timeout: 10) else {
            XCTFail("the ask bar is missing")
            return nil
        }
        input.tap()
        input.typeText(words + "\n")

        let receipt = app.staticTexts["mira.receipt"]
        if receipt.waitForExistence(timeout: turnWait) {
            let label = receipt.label
            app.buttons["mira.revert"].firstMatch.tap()   // leave the page as we found it
            return label
        }
        if !expectReceipt { return nil }
        XCTFail("\"\(words)\" produced no canvas change; on screen: "
            + app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: " | "))
        return nil
    }

    func testAPersonBuildsAPageAndAsksMiraForTheThingsThisWorkEnables() {
        // 1. A page, the way anyone starts one.
        app.buttons["Start a memory"].tap()

        // 2. A real photo.
        app.buttons["Image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 10), "the sample photo source is there")
        samples.tap()

        // 3. Real words, so the page has something to reason about.
        let textTool = app.buttons["Text"]
        XCTAssertTrue(textTool.waitForExistence(timeout: 10), "back on the canvas")
        textTool.tap()
        app.typeText("Lunch by the river")
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }

        // 4. The asks. Each was broken or impossible before this work.
        let moved = ask("move the title below the photo")
        XCTAssertNotNil(moved, "geometry: Mira can place things")

        let layered = ask("put the photo behind everything else")
        XCTAssertNotNil(layered, "layering: used to die on a photo-treatment error")

        let resized = ask("make the photo bigger")
        XCTAssertNotNil(resized, "sizing: used to silently resize the TEXT")

        let retitled = ask("the title is too small")
        XCTAssertNotNil(retitled, "the title branch used to write a NEW title instead")

        // The wording depends on how many elements Mira chose to move,
        // which is hers to decide -- the deterministic receipt rules are
        // pinned by unit tests. Here it only has to land as a change.
        let tidied = ask("tidy this page up")
        XCTAssertNotNil(tidied, "whole-page rearrange is model-driven now, not a fixed stack")

        // 5. A question, which must NOT touch the canvas.
        let talked = ask("how does this page look to you?", expectReceipt: false)
        XCTAssertNil(talked, "a question is answered, not applied")
        XCTAssertTrue(
            app.buttons["mira.dismissReply"].waitForExistence(timeout: turnWait),
            "the answer arrives as a reply card"
        )
    }
}
