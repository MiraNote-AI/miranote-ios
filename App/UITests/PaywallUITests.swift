import StoreKitTest
import XCTest

/// api #95 step 4: an action that finds its free allowance used up opens
/// the paywall, which says what Guideline 3.1.2 asks for; buying in the
/// local StoreKit session gives Plus and the action works again. Under
/// `-AI-LIMIT-REACHED` the text service answers the AI services' 429 quota
/// body until the writer has Plus (UITestLimitedText).
final class PaywallUITests: XCTestCase {
    private var app: XCUIApplication!
    private var session: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        session = try SKTestSession(configurationFileNamed: "MiraNote")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        app = XCUIApplication()
        app.launchArguments = ["-UITEST", "-AI-LIMIT-REACHED"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session = nil
        app = nil
    }

    private var field: XCUIElement { app.descendants(matching: .any)["canvas.textEditor"] }
    private var paywall: XCUIElement { app.staticTexts["paywall.title"] }

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

    private func fieldValueContains(_ words: String, timeout: TimeInterval = 5) -> Bool {
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", words), object: field)
        return XCTWaiter().wait(for: [reads], timeout: timeout) == .completed
    }

    func testLimitReachedOpensThePaywallWithItsDisclosures() {
        startWriting("noodle shop")
        expand()

        XCTAssertTrue(paywall.waitForExistence(timeout: 5), "the used-up allowance opens the paywall")
        XCTAssertTrue(app.staticTexts["paywall.disclosure"].exists, "auto-renewal is stated")
        XCTAssertTrue(app.buttons["paywall.terms"].exists)
        XCTAssertTrue(app.buttons["paywall.privacy"].exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        XCTAssertEqual(probeMax("plus"), 0)
    }

    func testBuyingPlusInThePaywallLiftsTheLimit() throws {
        // From xcodebuild, storekitd on iOS 26.3 and later refuses the
        // configuration ("not installed for development") and StoreKit falls
        // back to the sandbox, where a purchase waits forever. iOS 26.2
        // accepts it, as does a run from Xcode after one Cmd+R.
        try XCTSkipIf(session.storefront != "USA", "storekitd refused the StoreKit configuration")
        startWriting("noodle shop")
        expand()
        XCTAssertTrue(paywall.waitForExistence(timeout: 5))
        let monthly = app.buttons["paywall.plan.ai.miranote.app.plus.monthly"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 10), "the plans load from the StoreKit session")
        XCTAssertTrue(app.staticTexts["$5.99 a month"].exists, "price and period")
        XCTAssertTrue(app.staticTexts["Introductory offer: $2.99 a month for 2 months, then $5.99 a month."].exists,
                      "the offer and the price after it")

        monthly.tap()
        app.buttons["paywall.subscribe"].tap()

        XCTAssertTrue(paywall.waitForNonExistence(timeout: 15), "bought: the paywall closes")
        XCTAssertEqual(probeMax("plus"), 1)
        XCTAssertGreaterThanOrEqual(probeMax("plusSyncs"), 1, "the server was told")

        expand()
        XCTAssertTrue(fieldValueContains("(expanded draft -- mock)"), "with Plus the action works")
    }

    func testThePaywallClosesWithoutBuying() {
        startWriting("noodle shop")
        expand()
        XCTAssertTrue(paywall.waitForExistence(timeout: 5))

        app.buttons["paywall.close"].tap()

        XCTAssertTrue(paywall.waitForNonExistence(timeout: 5))
        XCTAssertEqual(probeMax("plus"), 0)
        XCTAssertTrue(field.exists, "the page is still there to write on")
    }

    func testSettingsShowsTheFreePlanAndOpensThePaywall() {
        app.buttons["home.settings"].tap()
        let plan = app.staticTexts["settings.plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        if !app.buttons["settings.seePlans"].isHittable { app.swipeUp() }
        XCTAssertEqual(plan.label, "Free plan")
        XCTAssertTrue(app.buttons["settings.restore"].exists, "Restore Purchases in Settings")

        app.buttons["settings.seePlans"].tap()

        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["paywall.title"].label, "MiraNote Plus")
    }
}
