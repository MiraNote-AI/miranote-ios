import XCTest

/// Opening a push and what follows (D1-D4, E1-E6, F1-F5).
extension PhotoTriggerUITests {
    // MARK: Opening (D2b, D3, D4)

    func testTapOnPushOpensStory() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 8), "the push opened its story")
        shot("d1-story-from-push")
    }

    /// A killed app launched by the tap: the same memory, no regrouping or
    /// backend call (the scripted backend is not reachable here).
    func testColdLaunchFromPushOpensSameMemory() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        app.terminate()
        launch(["-TRIGGER-OPEN-PUSH", "latest", "-TRIGGER-BACKEND-DOWN"], keep: true)
        let label = app.staticTexts["trigger.firstFrameLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        XCTAssertEqual(label.label, groupADate)
        XCTAssertTrue(photo(1, of: 8).exists)
    }

    /// A push that arrives while a page is being edited waits: the editor
    /// is not torn down (its words would be lost); the story opens once the
    /// page is closed, and the page is filed.
    func testPushWaitsForAnOpenEditor() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        app.terminate()
        let launched = Date()
        launch(["-TRIGGER-OPEN-PUSH-AFTER", "20"], keep: true)
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].tap()
        let field = app.descendants(matching: .any)["canvas.textEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("kept while the push waits")
        app.buttons["keyboard.done"].tap()
        XCTAssertLessThan(Date().timeIntervalSince(launched), 20, "the page was open before the push came")
        Thread.sleep(forTimeInterval: max(0, 24 - Date().timeIntervalSince(launched)))
        XCTAssertFalse(photo(1, of: 8).exists, "the story waits for the editor")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.exists, "the editor is still up")
        shot("c1-editor-kept")
        save.tap()
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 10), "the story opens once the page is closed")
        app.buttons["trigger.close"].tap()
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(app.buttons["note.kept while the push waits"].waitForExistence(timeout: 5), "the page was filed")
    }

    func testMissingPhotosUnderThreeStaysHome() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush(["-TRIGGER-MISSING", "6"])
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(photo(1, of: 2).exists)
        XCTAssertTrue(app.buttons["Start a memory"].isHittable, "Home, quietly")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testMissingPhotosPlayWhatRemains() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        // Photos 1-2 of the ten sent are gone: six of the story's eight stay.
        openLatestPush(["-TRIGGER-MISSING", "2"])
        XCTAssertTrue(photo(1, of: 6).waitForExistence(timeout: 8))
    }

    // MARK: Story and ending (E1-E6)

    func testStoryStartsWithPeakAndLabel() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush(["-TRIGGER-SLOW-STORY"])
        // The fake AI's peak is the best-scoring photo, the sixth sent (P6).
        let first = app.descendants(matching: .any)["trigger.photo.P6"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertEqual(first.label, "Photo 1 of 8")
        XCTAssertTrue(app.staticTexts["trigger.firstFrameLabel"].exists)
        shot("e1-peak-first")
        // Then the rest by time, the earliest (P1) next. (The 3 s / 2 s dwell
        // is TriggerMemoryTests'; this run plays it 4x slower.)
        let right = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        right.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trigger.photo.P1"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["trigger.photo.P1"].label, "Photo 2 of 8")
        // Only the first photo carries words: faded out, checked by eye here.
        Thread.sleep(forTimeInterval: 0.5)
        shot("e1-second-photo")
        right.tap()
        XCTAssertEqual(app.descendants(matching: .any)["trigger.photo.P2"].label, "Photo 3 of 8")
    }

    func testEndingOrderAndNoDetailRow() {
        // The scripted backend's memory has a detail line.
        launch()
        pushAndWait()
        openLatestPush()
        _ = skipToEnding(photos: 8)
        let fact = app.staticTexts["trigger.factLine"]
        let detail = app.staticTexts["trigger.detail"]
        let question = app.staticTexts["trigger.question"]
        let keep = app.buttons["trigger.keep"]
        XCTAssertTrue(detail.exists)
        XCTAssertLessThan(fact.frame.maxY, detail.frame.minY)
        XCTAssertLessThan(detail.frame.maxY, question.frame.minY)
        XCTAssertLessThan(question.frame.maxY, keep.frame.minY)
        XCTAssertEqual(keep.label, "Keep this afternoon")
        shot("e3-ending-with-detail")

        // The fake AI has none: no row, the question right under the fact.
        app.terminate()
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        _ = skipToEnding(photos: 8)
        XCTAssertFalse(app.staticTexts["trigger.detail"].exists)
        let gap = app.staticTexts["trigger.question"].frame.minY - app.staticTexts["trigger.factLine"].frame.maxY
        XCTAssertLessThan(gap, 30, "no empty row where the detail would be")
        shot("e3-ending-no-detail")
    }

    /// Three photos and eight: the gather as a burst (E2, checked by eye).
    func testGatherBurstForThreeAndEight() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 8))
        let right = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        for _ in 0..<7 { right.tap() }
        Thread.sleep(forTimeInterval: 1.6)
        for frame in 0..<12 { shot(String(format: "e2-gather8-%02d", frame)) }
        XCTAssertTrue(app.buttons["trigger.keep"].waitForExistence(timeout: 4))

        // Group C, rank 3, has three photos.
        app.terminate()
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait("trigger.pushNext")
        for rank in [2, 3] {
            app.buttons["trigger.pushNext"].tap()
            XCTAssertTrue(progressLine("Scheduled, the push comes in 10 s (rank \(rank)").waitForExistence(timeout: 20))
        }
        openLatestPush()
        XCTAssertTrue(photo(1, of: 3).waitForExistence(timeout: 8))
        for _ in 0..<2 { right.tap() }
        Thread.sleep(forTimeInterval: 1.6)
        for frame in 0..<12 { shot(String(format: "e2-gather3-%02d", frame)) }
        XCTAssertTrue(app.buttons["trigger.keep"].waitForExistence(timeout: 4))
    }

    func testCloseReturnsHome() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 8))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 4))
        // And from the ending.
        openLatestPush()
        _ = skipToEnding(photos: 8)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 4))
    }

    func testFewerLikeThisShowsNoteAndContinues() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush(["-TRIGGER-SLOW-STORY"])
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 8))
        app.buttons["More"].tap()
        app.buttons["Fewer like this"].tap()
        let note = app.staticTexts["trigger.menuNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        XCTAssertTrue(note.label.hasPrefix("Fewer like \""), note.label)
        shot("e5-fewer-like-this")
        // The note goes after 2 s, the story where it was, and plays on.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: note)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(photo(1, of: 8).exists, "still the first photo")
        XCTAssertTrue(photo(2, of: 8).waitForExistence(timeout: 16), "the story carries on")
    }

    func testNotThisDayReturnsHome() {
        launch(["-TRIGGER-FAKE-AI"])
        pushAndWait()
        openLatestPush()
        XCTAssertTrue(photo(1, of: 8).waitForExistence(timeout: 8))
        app.buttons["More"].tap()
        app.buttons["Not this day"].tap()
        XCTAssertEqual(app.staticTexts["trigger.menuNote"].waitForExistence(timeout: 2) ? "shown" : "missing", "shown")
        XCTAssertEqual(app.staticTexts["trigger.menuNote"].label, "This day won't be pushed again")
        shot("e5-not-this-day")
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 5))
    }

    // MARK: Canvas draft (F1-F5)

    func testCtaOpensCanvasAndSaveListsOnHome() {
        launch()
        pushAndWait()
        openLatestPush()
        skipToEnding(photos: 8).tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the canvas opened")
        XCTAssertTrue(app.staticTexts["A quiet light on the table"].waitForExistence(timeout: 4), "the detail line")
        XCTAssertTrue(app.staticTexts["What was on the table?"].exists, "the question")
        shot("f1-canvas")
        save.tap()
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 6))
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 4))
        shot("f5-home")
        log.tap()
        // Filed under its title: the fact line, the page's top, largest text (F4).
        XCTAssertTrue(app.buttons["note.\(groupADate)"].waitForExistence(timeout: 5))
    }

    func testDraftSurvivesRelaunch() {
        launch()
        pushAndWait()
        openLatestPush()
        skipToEnding(photos: 8).tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.buttons["collection.Daily Log"].waitForExistence(timeout: 6))
        app.terminate()
        launch(keep: true)
        let log = app.buttons["collection.Daily Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 8), "the page is still filed after a relaunch")
        log.tap()
        // Filed under its title: the fact line, the page's top, largest text (F4).
        XCTAssertTrue(app.buttons["note.\(groupADate)"].waitForExistence(timeout: 5))
    }
}
