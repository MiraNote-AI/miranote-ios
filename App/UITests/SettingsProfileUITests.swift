import XCTest

/// Handoff 2026-10-24 screens 01-07: Home's settings and profile circles,
/// the Settings screens' persisted choices and the Edit Profile sheet. The
/// preferences live in the simulator's defaults across runs, so each test
/// picks a choice that is not the current one rather than assuming a start.
final class SettingsProfileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func openSettings() {
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        XCTAssertEqual(gear.label, "Settings")
        gear.tap()
        XCTAssertTrue(app.buttons["settings.appearance"].waitForExistence(timeout: 5))
    }

    private func relaunch() {
        app.terminate()
        app.launch()
    }

    /// The option ids of a screen and the one currently selected.
    private func choose(otherThanSelectedAmong ids: [String]) -> String {
        let options = ids.map { app.buttons[$0] }
        XCTAssertTrue(options[0].waitForExistence(timeout: 5))
        let selected = options.filter(\.isSelected)
        XCTAssertEqual(selected.count, 1, "exactly one choice is selected")
        let next = ids.first { !app.buttons[$0].isSelected }!
        app.buttons[next].tap()
        XCTAssertTrue(app.buttons[next].isSelected)
        XCTAssertEqual(options.filter(\.isSelected).count, 1, "single choice")
        return next
    }

    func testAppearanceChoicePersistsAfterRelaunch() {
        openSettings()
        app.buttons["settings.appearance"].tap()
        let ids = ["appearance.system", "appearance.forest", "appearance.sunlitPop"]
        let picked = choose(otherThanSelectedAmong: ids)
        let title = ["appearance.system": "System", "appearance.forest": "Forest",
                     "appearance.sunlitPop": "Sunlit Pop"][picked]!

        app.buttons["settings.back"].tap()
        XCTAssertEqual(app.buttons["settings.appearance"].value as? String, title, "the overview row shows the choice")

        relaunch()
        openSettings()
        XCTAssertEqual(app.buttons["settings.appearance"].value as? String, title)
        app.buttons["settings.appearance"].tap()
        XCTAssertTrue(app.buttons[picked].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[picked].isSelected, "the choice survives a relaunch")
    }

    /// Forest redraws Home at once (no relaunch) and stays after one;
    /// System brings the original back. Ends on System for the next run.
    func testForestThemeAppliesLiveAndPersists() {
        let home = app.descendants(matching: .any)["home.root"]
        openSettings()
        app.buttons["settings.appearance"].tap()
        app.buttons["appearance.forest"].tap()
        app.buttons["settings.back"].tap()
        app.buttons["settings.back"].tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(home.value as? String, "forest", "Home switches without a relaunch")

        relaunch()
        XCTAssertTrue(home.waitForExistence(timeout: 8))
        XCTAssertEqual(home.value as? String, "forest", "the theme survives a relaunch")

        openSettings()
        app.buttons["settings.appearance"].tap()
        app.buttons["appearance.system"].tap()
        app.buttons["settings.back"].tap()
        app.buttons["settings.back"].tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(home.value as? String, "system", "System restores the original Home")
    }

    func testLanguageChoicePersistsAfterRelaunch() {
        openSettings()
        app.buttons["settings.language"].tap()
        let picked = choose(otherThanSelectedAmong: ["language.en-US", "language.zh-CN"])
        let title = picked == "language.en-US" ? "English" : "\u{4E2D}\u{6587}"

        app.buttons["settings.back"].tap()
        XCTAssertEqual(app.buttons["settings.language"].value as? String, title)

        relaunch()
        openSettings()
        app.buttons["settings.language"].tap()
        XCTAssertTrue(app.buttons[picked].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[picked].isSelected)
    }

    func testTextSizeAdjustsAndPersists() {
        openSettings()
        let slider = app.otherElements["settings.textSize"]
        XCTAssertTrue(slider.exists)
        let before = slider.value as? String
        // A tap on the rail moves the thumb there: a quarter of the way
        // along (90%) unless it is already there, then three quarters.
        let target = before == "90 percent" ? 0.75 : 0.25
        let frame = slider.frame
        let railStart = frame.minX + 30, railWidth = frame.width - 67
        let point = CGVector(dx: railStart + railWidth * target, dy: frame.maxY - 36)
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
        let after = slider.value as? String
        XCTAssertNotEqual(before, after)

        relaunch()
        openSettings()
        XCTAssertEqual(app.otherElements["settings.textSize"].value as? String, after)
    }

    func testHomeProfileOpensProfileAndSaveShowsTheName() {
        let circle = app.buttons["home.profile"]
        XCTAssertTrue(circle.waitForExistence(timeout: 8))
        XCTAssertEqual(circle.label, "Profile")
        circle.tap()
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))

        app.buttons["profile.edit"].tap()
        let field = app.textFields["profile.sheet.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let save = app.buttons["profile.sheet.save"]
        XCTAssertFalse(save.isEnabled, "nothing changed yet")

        clear(field)
        XCTAssertFalse(save.isEnabled, "a name is required")
        let name = "Ada \(Int.random(in: 1000...9999))"
        field.typeText(name)
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Save closes the sheet")
        XCTAssertEqual(app.buttons["profile.name"].label, name)
    }

    func testCloseDiscardsTheEdit() {
        app.buttons["home.profile"].tap()
        let nameButton = app.buttons["profile.name"]
        XCTAssertTrue(nameButton.waitForExistence(timeout: 5))
        let saved = nameButton.label

        nameButton.tap()
        let field = app.textFields["profile.sheet.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" unsaved")
        app.buttons["profile.sheet.close"].tap()

        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(nameButton.label, saved, "Close keeps the saved name")
    }

    private func clear(_ field: XCUIElement) {
        // Past the words, so the cursor lands at their end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        let count = current == placeholder ? 0 : current.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }
}
