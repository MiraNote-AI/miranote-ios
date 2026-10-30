import XCTest

/// Save is the one way a page becomes saved (#137): Home keeps it as a
/// draft -- a toast says so and the journal cover is tagged -- except a
/// saved page left unchanged, which stays saved. The star jar holds a page
/// once Save has filed it, and a draft keeps the mood its last Save got.
final class DraftPagesUITests: XCTestCase {
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

    private var draftToast: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "draft.toast").firstMatch
    }

    func testHomeKeepsANewPageAsADraft() {
        app.buttons["Start a memory"].tap()
        addTextBlock("picnic under the plane trees")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5), "leaving says the page was kept as a draft")
        keepScreenshot("draft toast")

        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.picnic under the plane trees"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
        keepScreenshot("draft tag")
    }

    // Started from a journal's "+ New memory": the draft stays in that
    // journal, and the toast shows over its bottom bar (kept for review).
    func testAPageStartedInAJournalStaysThereAsADraft() {
        app.buttons["collection.Travel Scrapbook"].tap()
        app.buttons["note.add"].tap()
        addTextBlock("ferry at dawn")
        // The journal's own Home button is still there under the editor:
        // tap the editor's by its id.
        app.buttons["nav.leading"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))
        keepScreenshot("draft toast in a journal")

        let cover = app.buttons["note.ferry at dawn"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
    }

    func testSaveTurnsADraftIntoASavedPage() {
        app.buttons["Start a memory"].tap()
        addTextBlock("picnic under the plane trees")
        app.buttons["Home"].tap()
        // The toast shows once the editor is gone: wait for it before
        // waiting it out.
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))
        waitUntilGone(draftToast)
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.picnic under the plane trees"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")

        cover.tap()
        app.buttons["reading.edit"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft")
    }

    func testChangingASavedPageWithoutSaveMakesItADraft() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft", "seeded pages are saved")

        cover.tap()
        app.buttons["reading.edit"].tap()
        addTextBlock("and a second coffee")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
    }

    // A saved page only looked at stays saved. The seeded page's text
    // already fits, so the opening re-measure moves nothing here: its guard
    // is DraftPageTests.testTheOpeningRemeasureIsNoEdit. (No waiting on the
    // toast NOT to show: a miss over the reading page took XCUITest ten
    // minutes to describe. The cover says it plainly.)
    func testLookingAtASavedPageKeepsItSaved() {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.Lunch by the river"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        app.buttons["reading.edit"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Home"].tap()

        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft")
    }

    // The Draft tag makes a card's caption taller than its neighbor's (a
    // long date at a large text size even puts the tag on a line of its
    // own): the row is top-aligned, so the covers still line up. The
    // seeded "Slow morning" page is dated today, like the new draft.
    func testADraftsCoverLinesUpWithTheSavedOneBesideIt() {
        app.buttons["Start a memory"].tap()
        addTextBlock("A rainy draft")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))

        app.buttons["collection.Daily Log"].tap()
        let draft = app.buttons["note.A rainy draft"]
        let saved = app.buttons["note.Slow morning, good coffee"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Draft")
        XCTAssertEqual(draft.frame.minY, saved.frame.minY, accuracy: 0.5, "the two covers share a top")
    }

    // MARK: The star jar: a page is a star once Save files it

    func testADraftIsNoStarUntilItIsSaved() {
        app.buttons["Start a memory"].tap()
        addTextBlock("A happy draft")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))

        openJar()
        XCTAssertTrue(app.staticTexts["jar.summary"].waitForExistence(timeout: 5), "the seed's stars are in")
        XCTAssertFalse(app.buttons["jar.star.A happy draft"].exists, "a draft never saved is no star")
        app.buttons["Home"].tap()

        saveUnchanged("A happy draft")
        openJar()
        let star = app.buttons["jar.star.A happy draft"]
        XCTAssertTrue(star.waitForExistence(timeout: 5), "saved, it is a star")
        label(of: star, becomes: "A happy draft, Joyful")
    }

    // The mock reads "sad" as low, but "happy" first: judged from the
    // draft's words, the star would turn joyful before the next Save.
    func testASavedPageLeftAsADraftKeepsItsStarAndMood() {
        app.buttons["Start a memory"].tap()
        addTextBlock("A sad walk")
        app.buttons["Save"].tap()
        openJar()
        let star = app.buttons["jar.star.A sad walk"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        label(of: star, becomes: "A sad walk, Low")
        app.buttons["Home"].tap()

        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.A sad walk"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        app.buttons["reading.edit"].tap()
        addTextBlock("then a happy dinner")
        app.buttons["Home"].tap()
        XCTAssertTrue(draftToast.waitForExistence(timeout: 5))
        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.value as? String, "Draft")
        app.buttons["Home"].tap()

        openJar()
        XCTAssertTrue(star.waitForExistence(timeout: 5), "a saved page's draft keeps its star")
        label(of: star, staysAt: "A sad walk, Low", for: 3)
        app.buttons["Home"].tap()

        saveUnchanged("A sad walk")
        openJar()
        label(of: star, becomes: "A sad walk, Joyful")
    }

    private func openJar() {
        let entry = app.buttons["home.starJar"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.staticTexts["Star jar"].waitForExistence(timeout: 5))
    }

    /// From Home: opens the Daily Log page `title`, taps Save without a
    /// change, and comes back Home.
    private func saveUnchanged(_ title: String) {
        app.buttons["collection.Daily Log"].tap()
        let cover = app.buttons["note.\(title)"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.tap()
        app.buttons["reading.edit"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        app.buttons["reading.back"].tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cover.value as? String, "Draft")
        app.buttons["Home"].tap()
    }

    private func label(of element: XCUIElement, becomes expected: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: 8), .completed,
                       "label is \(element.label), expected \(expected)")
    }

    /// Nothing changes the label for `seconds`: a mood ask answers in
    /// well under that (the mock takes 0.3 s).
    private func label(of element: XCUIElement, staysAt expected: String, for seconds: TimeInterval) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", expected),
                                                object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: seconds), .timedOut,
                       "label became \(element.label)")
    }

    /// Adds a text block through the Text tool and closes the keyboard.
    private func addTextBlock(_ text: String) {
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    /// For the design review of the toast and the tag.
    private func keepScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: 5)
    }
}
