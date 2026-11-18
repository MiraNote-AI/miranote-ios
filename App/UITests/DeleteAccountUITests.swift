import XCTest

/// api #95 step 6: Settings > Delete account. The sheet says what is
/// deleted and what stays, that a subscription is not cancelled, and
/// links to Apple's subscriptions page; Delete asks to confirm, then the
/// mock Apple and accounts service answer (-UITEST). Pages stay.
final class DeleteAccountUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-UITEST"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
    }

    private var home: XCUIElement { app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch }

    private func openSettings() {
        if !app.buttons["home.settings"].exists { home.tap() }
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance"].waitForExistence(timeout: 5))
    }

    /// The sheet, then Delete and the alert's Delete.
    private func deleteAccount() {
        let delete = app.buttons["settings.deleteAccount"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts["What is deleted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What stays"].exists)
        XCTAssertTrue(app.staticTexts["Your subscription"].exists)
        XCTAssertTrue(app.links["deleteAccount.manageSubscriptions"].exists
                      || app.buttons["deleteAccount.manageSubscriptions"].exists, "Apple's subscriptions page")
        app.buttons["deleteAccount.delete"].tap()
        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "Delete asks to confirm first")
        alert.buttons["Delete"].tap()
    }

    private func writeAPage(_ words: String) {
        let journal = app.buttons["collection.Daily Log"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        app.buttons["note.add"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(words)
        app.buttons["keyboard.done"].tap()
        app.buttons["nav.trailing"].tap()
        XCTAssertTrue(app.buttons["note.\(words)"].waitForExistence(timeout: 8))
    }

    func testDeletingTheAccountSignsOutAndKeepsThePages() {
        launch()
        writeAPage("lantern festival")
        openSettings()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5))

        deleteAccount()

        let done = app.staticTexts["deleteAccount.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "the sheet says the account is deleted")
        XCTAssertFalse(app.staticTexts["deleteAccount.appleNotRevoked"].exists, "Apple was told")
        app.buttons["deleteAccount.close"].tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.signIn"].waitForExistence(timeout: 5), "Settings shows signed out")
        XCTAssertFalse(app.buttons["settings.deleteAccount"].exists)

        app.buttons["settings.back"].tap()
        let journal = app.buttons["collection.Daily Log"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        XCTAssertTrue(app.buttons["note.lantern festival"].waitForExistence(timeout: 5), "the page is still here")
    }

    func testCancelOnTheAlertDeletesNothing() {
        launch()
        openSettings()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5))
        app.buttons["settings.deleteAccount"].tap()
        XCTAssertTrue(app.buttons["deleteAccount.delete"].waitForExistence(timeout: 5))
        app.buttons["deleteAccount.delete"].tap()
        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Cancel"].tap()
        app.buttons["deleteAccount.cancel"].tap()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5), "still signed in")
    }

    /// A 401 is also what the server answers once the account is deleted
    /// (an earlier try whose answer was lost, another device): the sheet
    /// does not say nothing was deleted, offers no Try again, and Settings
    /// shows signed out.
    func testAnEndedSignInSaysToSignInAgainAndOffersNoRetry() {
        launch(["-DELETE-ACCOUNT-ENDED"])
        openSettings()
        deleteAccount()

        let error = app.staticTexts["deleteAccount.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("Sign in again"), error.label)
        XCTAssertFalse(error.label.contains("nothing was deleted"), error.label)
        XCTAssertFalse(app.buttons["deleteAccount.delete"].exists, "signed out, a try cannot reach the server")
        app.buttons["deleteAccount.cancel"].tap()
        XCTAssertTrue(app.buttons["settings.signIn"].waitForExistence(timeout: 5), "the dead tokens are gone")
    }

    func testOfflineSaysNothingWasDeletedAndKeepsTheSignIn() {
        launch(["-DELETE-ACCOUNT-OFFLINE"])
        openSettings()
        deleteAccount()

        let error = app.staticTexts["deleteAccount.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("nothing was deleted"), error.label)
        XCTAssertTrue(app.buttons["deleteAccount.delete"].label.contains("Try again"))
        app.buttons["deleteAccount.cancel"].tap()
        XCTAssertTrue(app.staticTexts["settings.signedIn"].waitForExistence(timeout: 5), "still signed in")
        XCTAssertTrue(app.buttons["settings.deleteAccount"].exists)
    }
}
