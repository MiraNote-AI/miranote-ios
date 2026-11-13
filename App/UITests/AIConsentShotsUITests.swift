import XCTest

/// Photographs the "How Mira uses AI" sheet (Details open) and Settings'
/// AI & privacy card, in English and Simplified Chinese (#151). The photos
/// ride along as attachments; with SHOTS_DIR set (TEST_RUNNER_SHOTS_DIR for
/// xcodebuild) they are also written there.
final class AIConsentShotsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            )
        }
    }

    private func walk(language: String?, suffix: String) {
        app.launchArguments = ["-UITEST", "-AI-CONSENT-ASK"]
            + (language.map { ["-AppleLanguages", "(\($0))"] } ?? [])
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 8))

        app.buttons["home.settings"].tap()
        let mood = app.switches["settings.moodFromWords"]
        XCTAssertTrue(mood.waitForExistence(timeout: 5))
        app.swipeUp()
        shot("settings-ai-privacy-\(suffix)")

        mood.tap()
        XCTAssertTrue(app.staticTexts["aiConsent.title"].waitForExistence(timeout: 5))
        shot("consent-sheet-\(suffix)")
        app.buttons["aiConsent.details"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["aiConsent.detailsList"].waitForExistence(timeout: 3))
        shot("consent-sheet-details-\(suffix)")
        app.swipeUp()
        shot("consent-sheet-details-end-\(suffix)")
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(app.buttons["settings.aiWithdraw"].waitForExistence(timeout: 5))
        shot("settings-ai-privacy-granted-\(suffix)")
    }

    func testEnglish() {
        walk(language: nil, suffix: "en")
    }

    func testSimplifiedChinese() {
        walk(language: "zh-Hans", suffix: "zh")
    }
}
