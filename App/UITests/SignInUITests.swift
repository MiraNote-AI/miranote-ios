import XCTest

/// api #95 step 2: Sign in with Apple right after AI consent at the first
/// server-AI action, Not now cancelling only that action, and Sign out in
/// Settings. Apple and the accounts service are mocks under -UITEST; other
/// suites launch signed in, these with `-SIGN-IN-ASK`. `aiSent` in the
/// debug probe counts the requests let past consent and sign-in.
final class SignInUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
    }

    private var consentSheet: XCUIElement { app.staticTexts["aiConsent.title"] }
    private var signInSheet: XCUIElement { app.staticTexts["signIn.title"] }
    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }

    private func startWriting(_ words: String) {
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    private func expand() {
        if !app.buttons["style.ai.expand"].exists { app.buttons["style.ai"].tap() }
        app.buttons["style.ai.expand"].tap()
    }

    private func probeMax(_ key: String) -> Int {
        let probes = app.descendants(matching: .any).matching(identifier: "debug.state").allElementsBoundByIndex
        return probes.compactMap { probe -> Int? in
            guard let data = probe.label.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return state[key] as? Int
        }.max() ?? -1
    }

    private var signInLine: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "Sign in to use Mira", "Sign in to use Mira"
        )).firstMatch
    }

    private func fieldValueContains(_ words: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", words), object: field)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    private func openSettings() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance"].waitForExistence(timeout: 5))
    }

    // MARK: Tests

    func testFirstAIActionAsksConsentThenSignInThenProceeds() {
        launch(["-AI-CONSENT-ASK", "-SIGN-IN-ASK"])
        XCTAssertFalse(signInSheet.exists, "nothing at launch")
        startWriting("noodle shop")
        XCTAssertEqual(probeMax("signedIn"), 0, "writing needs no account")
        expand()

        XCTAssertTrue(consentSheet.waitForExistence(timeout: 5), "consent first")
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 5), "then sign-in")
        XCTAssertEqual(probeMax("aiSent"), 0, "nothing sent while asking")
        let apple = app.buttons["signIn.apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 3))
        apple.tap()

        XCTAssertTrue(signInSheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"), "signed in: the action goes on")
        XCTAssertEqual(probeMax("signedIn"), 1)
        XCTAssertEqual(probeMax("aiSent"), 1)

        app.buttons["style.ai.clean"].tap()
        XCTAssertFalse(signInSheet.waitForExistence(timeout: 2), "never asked again")
        XCTAssertFalse(consentSheet.exists)
        XCTAssertEqual(probeMax("aiSent"), 2)
    }

    func testNotNowOnSignInCancelsOnlyThatAction() {
        launch(["-AI-CONSENT-ASK", "-SIGN-IN-ASK"])
        startWriting("noodle shop")
        expand()
        XCTAssertTrue(consentSheet.waitForExistence(timeout: 5))
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 5))
        app.buttons["signIn.notNow"].tap()

        XCTAssertTrue(signInSheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(fieldValueContains("(expanded draft -- mock)", timeout: 2), "Not now: no rewrite")
        XCTAssertTrue(signInLine.waitForExistence(timeout: 3), "the rewrite row says why")
        XCTAssertEqual(probeMax("aiSent"), 0, "Not now: nothing was sent")
        XCTAssertEqual(probeMax("signedIn"), 0)
        XCTAssertTrue(field.exists, "the page is still there to write on")

        // Consent is kept; the next AI action asks only to sign in.
        expand()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 5))
        XCTAssertFalse(consentSheet.exists)
        app.buttons["signIn.apple"].tap()
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"))
        XCTAssertEqual(probeMax("aiSent"), 1)
    }

    func testSignOutFromSettingsAsksAgainAtTheNextAIAction() {
        launch([])
        openSettings()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5))
        let signOut = app.buttons["settings.signOut"]
        signOut.tap()
        let signIn = app.buttons["settings.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Settings shows signed out")
        XCTAssertFalse(app.staticTexts["settings.signedIn"].exists)
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))

        startWriting("tea")
        expand()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 5), "signed out: the next AI action asks")
        app.buttons["signIn.apple"].tap()
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"))
    }

    /// A build that names no accounts service (the default until it is
    /// deployed): AI asks for consent only, never to sign in, and Settings
    /// offers no sign-in.
    func testNoAccountsServiceAsksOnlyForConsent() {
        launch(["-AI-CONSENT-ASK", "-SIGN-IN-ASK", "-NO-ACCOUNTS"])
        startWriting("noodle shop")
        expand()
        XCTAssertTrue(consentSheet.waitForExistence(timeout: 5), "consent still asks")
        app.buttons["aiConsent.continue"].tap()
        XCTAssertTrue(consentSheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(signInSheet.waitForExistence(timeout: 2), "no sign-in to ask for")
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"), "consent is enough")
        XCTAssertEqual(probeMax("aiSent"), 1)
        XCTAssertEqual(probeMax("signedIn"), 0)

        app.buttons["keyboard.done"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        openSettings()
        XCTAssertFalse(app.buttons["settings.signIn"].exists, "no ACCOUNT card")
        XCTAssertFalse(app.staticTexts["settings.signedIn"].exists)
    }

    func testSignInFromSettings() {
        launch(["-SIGN-IN-ASK"])
        openSettings()
        let signIn = app.buttons["settings.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 5))
        app.buttons["signIn.apple"].tap()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.signOut"].exists)
    }
}
