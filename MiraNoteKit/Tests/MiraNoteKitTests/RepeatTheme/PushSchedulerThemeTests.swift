import ImageIO
import XCTest
@testable import MiraNoteKit

/// "Test-push this theme" on the debug page (spec 6.10, F2): round 2, the
/// photo choice and the repeat compose, pushed in 10 s as a debug push.
final class PushSchedulerThemeTests: PushSchedulerTestCase {
    private var rounds: FakeRoundClient!
    static let center = [Float](repeating: 0, count: 8).enumerated().map { $0.offset == 0 ? 1 : $0.element }

    override func setUpWithError() throws {
        try super.setUpWithError()
        rounds = FakeRoundClient()
    }

    // MARK: - The push

    func testTryThemePushesInTenSecondsAsDebug() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids),
                               big("blocked", name: "Scale", members: [], status: .blocked)])
        let scheduler = scheduler()
        let steps = await press(scheduler, "big")

        XCTAssertEqual(steps, [.preparing, .checkingTheme(attempt: 1, theme: "Dinner", candidates: 10),
                               .composingTheme(theme: "Dinner", photos: 7), .scheduled(rank: 1, score: 0)])
        try assertRoundTwoSentTen()
        try assertSevenComposed()
        try assertDebugRow(of: ids)
    }

    func testTryThemeDoesNotChangeScheduleOrPushedDays() async throws {
        let ids = try seed("t", days: Array(12...20))
        try themeLibrary.save([big(members: ids)])
        let scheduler = scheduler()
        await scheduler.appBecameActive()
        let before = active
        let preferencesBefore = preferences.load()
        let steps = await press(scheduler, "big")
        guard case .scheduled = steps.last else { return XCTFail("\(steps)") }
        XCTAssertEqual(active, before, "the schedule is untouched")

        let debug = try XCTUnwrap(ledger.load().first(where: \.isDebug))
        clock.advance(60)
        notifier.pendingIds.remove(debug.identifier)
        clock.advance(3600)
        await scheduler.appBecameActive()
        let entries = ledger.load()
        XCTAssertNotNil(entries.first { $0.pushId == debug.pushId }?.deliveredAt)
        XCTAssertTrue(LedgerReconciler.pushedDays(entries).isEmpty, "a test push never counts as pushed")
        XCTAssertTrue(LedgerReconciler.pushedPhotos(entries).isDisjoint(with: ids))
        XCTAssertEqual(active, before)
        XCTAssertEqual(preferences.load(), preferencesBefore)
        XCTAssertEqual(themeLibrary.load().map(\.status), [.active], "the theme stays as it was")
    }

    func testTryThemeSensitiveRefused() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids, status: .sensitive),
                               big("blocked", name: "Scale", members: ids, status: .blocked)])
        let scheduler = scheduler()
        let sensitive = await press(scheduler, "big")
        XCTAssertEqual(sensitive, [.preparing, .themeStopped(.sensitive)])
        let blocked = await press(scheduler, "blocked")
        XCTAssertEqual(blocked, [.preparing, .themeStopped(.blocked)])
        let unknown = await press(scheduler, "nope")
        XCTAssertEqual(unknown, [.preparing, .themeStopped(.unknownTheme)])
        XCTAssertTrue(rounds.roundTwoRequests.isEmpty, "nothing is sent")
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertTrue(notifier.scheduled.isEmpty)
        XCTAssertTrue(ledger.load().isEmpty)

        let without = makeScheduler()
        let notSetUp = await press(without, "big")
        XCTAssertEqual(notSetUp, [.preparing, .themeStopped(.notSetUp)])
    }

    func testContentThemeCandidatesUseEvidence() async throws {
        let weak = try seed("weak", days: Array(10...14), label: ("soup", 0.2), aesthetics: 0.9)
        let strong = try seed("strong", days: Array(10...14), label: ("soup", 0.8), aesthetics: 0.5)
        try themeLibrary.save([big(members: weak + strong), small("soup", name: "Soup", members: weak + strong)])
        _ = await press(scheduler(), "soup")
        XCTAssertEqual(Set(try XCTUnwrap(ledger.load().first).photoIds), Set(strong), "the strongest evidence wins")
    }

    func testSmallThemeUnderFiveDaysFallsBackToBig() async throws {
        let ids = try seed("t", days: Array(10...19))
        let soup = Array(ids.prefix(6))
        try themeLibrary.save([big(members: ids), small("soup", name: "Soup", members: soup),
                               small("tiny", name: "Tiny", members: Array(ids.prefix(3)))])
        // Round 2 takes two of the soup's six days away.
        rounds.roundTwoReply = { request, number in
            FakeRoundClient.roundTwoAnswer(request, notBelonging: number == 1 ? [1, 2] : [])
        }
        let scheduler = scheduler()
        let steps = await press(scheduler, "soup")
        XCTAssertEqual(rounds.roundTwoRequests.map(\.theme.name), ["Soup", "Dinner"])
        XCTAssertEqual(rounds.roundTwoRequests.map(\.photos.count), [6, 10])
        XCTAssertEqual(Array(steps.prefix(4)), [
            .preparing, .checkingTheme(attempt: 1, theme: "Soup", candidates: 6),
            .themeTryFailed(attempt: 1, reason: "Soup: 4 days left after round 2"),
            .checkingTheme(attempt: 2, theme: "Dinner", candidates: 10)
        ])
        guard case .scheduled = steps.last else { return XCTFail("\(steps)") }
        let entry = try XCTUnwrap(ledger.load().first)
        XCTAssertEqual(entry.themeId, "big", "the big theme is pushed")
        XCTAssertEqual(entry.themeName, "Dinner")
        XCTAssertEqual(entry.roundTwoTries, ["Soup: 4 days left after round 2"])
        XCTAssertEqual(entry.roundUsages?.count, 2)
        XCTAssertEqual((try repeatMeta()["theme"] as? [String: Any])?["id"] as? String, "big")

        // Under five days before round 2: falls back without asking.
        let second = await press(scheduler, "tiny")
        XCTAssertEqual(rounds.roundTwoRequests.map(\.theme.name), ["Soup", "Dinner", "Dinner"])
        XCTAssertEqual(second[1], .themeTryFailed(attempt: 1, reason: "Tiny: 3 days of photos"))
        XCTAssertEqual(ledger.load().last?.roundTwoTries, ["Tiny: 3 days of photos"])
    }

    func testAtMostThreeRoundTwoTries() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids)])
        rounds.roundTwoErrors = [ThemeRoundError.unreachable]
        rounds.roundTwoReply = { _, _ in "not json" }
        let scheduler = scheduler()
        let steps = await press(scheduler, "big")
        XCTAssertEqual(rounds.roundTwoRequests.count, 3, "three round-2 calls at most")
        let tries = [
            "Dinner: round 2 call failed (unreachable)", "Dinner: round 2 answer not used (notJSON)",
            "Dinner: round 2 answer not used (notJSON)"
        ]
        XCTAssertEqual(steps, [
            .preparing, .checkingTheme(attempt: 1, theme: "Dinner", candidates: 10),
            .themeTryFailed(attempt: 1, reason: tries[0]),
            .checkingTheme(attempt: 2, theme: "Dinner", candidates: 10),
            .themeTryFailed(attempt: 2, reason: tries[1]),
            .checkingTheme(attempt: 3, theme: "Dinner", candidates: 10),
            .themeStopped(.triesUsedUp(tries))
        ])
        XCTAssertEqual(roundLog.load().map(\.problem), [.notJSON, .notJSON], "every answer logged, never reused")
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertTrue(notifier.scheduled.isEmpty)
        XCTAssertTrue(ledger.load().isEmpty)
    }

    func testSimilarToStops() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids), small("soup", name: "Soup", members: ids)])
        rounds.roundTwoReply = { request, _ in FakeRoundClient.roundTwoAnswer(request, similar: ["Scale"]) }
        let steps = await press(scheduler(), "soup")
        XCTAssertEqual(steps.last, .themeStopped(.similar([RoundTwoAnswer.Similar(name: "Scale", level: "same")])))
        XCTAssertEqual(rounds.roundTwoRequests.count, 1, "not tried again, not with its big theme")
        XCTAssertTrue(client.submitted.isEmpty)
        XCTAssertTrue(ledger.load().isEmpty)
    }

    /// The fake-AI switch: no compose call, the memory made on the phone.
    func testFakeAIBuildsTheRepeatMemoryOnThePhone() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids)])
        fake = true
        let steps = await press(scheduler(), "big")
        guard case .scheduled = steps.last else { return XCTFail("\(steps)") }
        XCTAssertTrue(client.submitted.isEmpty, "nothing composed on the backend")
        let entry = try XCTUnwrap(ledger.load().first)
        let memory = try XCTUnwrap(records.load(entry.pushId)).memory
        XCTAssertTrue(memory.isFakeMade)
        XCTAssertEqual(memory.mode, "repeat")
        XCTAssertEqual(memory.story.photos.count, 7)
        // zh is "[key]" here: October alone, the noun in the button and the question.
        XCTAssertEqual(memory.push.title, "Dinner" + TriggerWords.separator + "[Month 10]")
        XCTAssertEqual(memory.ending.ctaLabel, "[Keep these dinner]")
        XCTAssertEqual(memory.ending.question, "[Three keywords for these dinner?]")
        XCTAssertEqual(memory.push.body, "[7 photos on 7 different days]")
        XCTAssertEqual(memory.ending.questionType, "one_word")
    }

    // MARK: - "Not this theme"

    /// The story's "Not this theme" (spec 6.9): the theme its push carries
    /// is blocked -- a test push of it is then refused -- and the ledger
    /// row records the choice. No day, bucket or V1 push is touched.
    func testNotThisThemeBlocksThePushedTheme() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids), big("sky", name: "Sky", members: [])])
        let scheduler = scheduler()
        await scheduler.appBecameActive()
        let before = active
        let preferencesBefore = preferences.load()
        let steps = await press(scheduler, "big")
        guard case .scheduled = steps.last else { return XCTFail("\(steps)") }
        let pushId = try XCTUnwrap(ledger.load().first(where: \.isDebug)?.pushId)

        let blocking = await scheduler.notThisTheme(pushId)
        XCTAssertNotNil(blocking, "there is a theme to block")
        await blocking?.value
        XCTAssertEqual(themeLibrary.load().map(\.status), [.blocked, .active])
        let entry = try XCTUnwrap(ledger.load().first { $0.pushId == pushId })
        XCTAssertEqual(entry.menuAction, .notThisTheme)
        XCTAssertEqual(entry.menuActionAt, clock.now)
        XCTAssertEqual(preferences.load(), preferencesBefore, "no day or bucket is blocked")
        XCTAssertEqual(active, before, "the schedule is untouched")
        let again = await press(scheduler, "big")
        XCTAssertEqual(again, [.preparing, .themeStopped(.blocked)])
    }

    /// With no ledger row (cleared), the push's record names the theme.
    func testNotThisThemeFindsTheThemeOnTheRecord() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids)])
        let scheduler = scheduler()
        _ = await press(scheduler, "big")
        let pushId = try XCTUnwrap(ledger.load().first?.pushId)
        try ledger.clear()
        await scheduler.menu(.notThisTheme, pushId: pushId)
        XCTAssertEqual(themeLibrary.load().map(\.status), [.blocked])
    }

    /// Neither a ledger row nor a record names a theme: nothing is blocked,
    /// the answer says so (no "won't be pushed again" note), no row is marked.
    func testNotThisThemeWithNeitherRowNorRecordBlocksNothing() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids)])
        let scheduler = scheduler()
        _ = await press(scheduler, "big")
        let pushId = try XCTUnwrap(ledger.load().first?.pushId)
        try ledger.clear()
        try records.remove(pushId)
        let blocking = await scheduler.notThisTheme(pushId)
        XCTAssertNil(blocking)
        await scheduler.menu(.notThisTheme, pushId: pushId)
        XCTAssertEqual(themeLibrary.load().map(\.status), [.active])
        XCTAssertTrue(ledger.load().isEmpty)

        // An id nothing knows of: the same.
        let unknown = await scheduler.notThisTheme("nope")
        XCTAssertNil(unknown)
    }

    /// A build with no theme engine cannot block: the row stays unmarked.
    func testNotThisThemeWithoutAThemeEngineBlocksNothing() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids)])
        _ = await press(scheduler(), "big")
        let pushId = try XCTUnwrap(ledger.load().first?.pushId)
        let without = makeScheduler()
        let blocking = await without.notThisTheme(pushId)
        XCTAssertNil(blocking)
        await without.menu(.notThisTheme, pushId: pushId)
        XCTAssertNil(ledger.load().first?.menuAction)
        XCTAssertNil(ledger.load().first?.menuActionAt)
        XCTAssertEqual(themeLibrary.load().map(\.status), [.active])
    }
}

// MARK: - Fixtures

extension PushSchedulerThemeTests {
    private var themeLibrary: ThemeLibrary { ThemeLibrary(file: folder.appendingPathComponent("themes/library.json")) }
    private var themePhotos: ThemePhotoStore { ThemePhotoStore(directory: folder.appendingPathComponent("themes/p")) }
    private var roundLog: RoundLog { RoundLog(file: folder.appendingPathComponent("themes/rounds.json")) }

    /// A large JPEG with GPS: what a round image is made from.
    private static let bigJPEG: Data = {
        guard let data = try? ComposeMetaTests.jpegWithGPS(width: 1200, height: 900) else { fatalError("no JPEG") }
        return data
    }()

    private func engine() -> ThemeEngine {
        let clock = self.clock!
        let zone = self.zone!
        return ThemeEngine(ThemeDependencies(
            library: library, analyzer: ThemeFakeAnalyzer(),
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), photos: themePhotos,
            themes: themeLibrary, rounds: roundLog,
            window: ThemeWindowStore(file: folder.appendingPathComponent("themes/window.json")),
            runs: ThemeRunLog(file: folder.appendingPathComponent("themes/runs.json")), client: rounds,
            imageData: { _ in Self.bigJPEG }, now: { clock.now }, calendar: zone.calendar))
    }

    private func scheduler() -> PushScheduler { makeScheduler(themeEngine: engine()) }

    /// 19:00 in Chicago, `days` before the test's start.
    private func evening(_ days: Int) -> Date { start.addingTimeInterval(-Double(days) * 86_400 + 8 * 3600) }

    /// One photo `<prefix>-<day>` a day at 19:00, in the library, with a theme record near the look.
    @discardableResult
    private func seed(_ prefix: String, days: [Int], label: (String, Float) = ("food", 0.9),
                      aesthetics: Double? = nil) throws -> [String] {
        var records: [ThemePhoto] = []
        for day in days {
            let id = "\(prefix)-\(day)"
            library.assetsList.append(LibraryAsset(id: id, takenAt: evening(day), location: nil,
                                                   isFavorite: day == days[0], isEdited: false, isScreenshot: false,
                                                   isHidden: false, isVideo: false,
                                                   originalFilename: "IMG_\(day).HEIC", burstId: nil))
            var raw = Self.center
            raw[1 + day % 7] = 0.3
            records.append(ThemePhoto(id: id, takenAt: evening(day), location: nil,
                                      labels: [LabelScore(id: label.0, confidence: label.1)],
                                      aesthetics: aesthetics ?? 0.5 + Double(day % 3) / 10, faces: 0, isTheme: true,
                                      print: ThemePhoto.normalized(raw), printRevision: 1))
        }
        try themePhotos.upsert(records, calendar: zone.calendar)
        return records.map(\.id)
    }

    private func big(_ id: String = "big", name: String = "Dinner", members: [String],
                     status: ThemeStatus = .active) -> ThemeRow {
        ThemeRow(id: id, kind: .big, parentId: nil, name: name, noun: "dinner", samePart: "home at dusk",
                 split: "A", status: status, center: Self.center, rule: nil, members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
    }

    private func small(_ id: String, name: String, members: [String]) -> ThemeRow {
        ThemeRow(id: id, kind: .small, parentId: "big", name: name, noun: "soup", samePart: "a bowl", split: "A",
                 status: .active, center: nil, rule: .content(evidence: ["soup"]), members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil,
                 where: WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20,
                                   weekpart: "weekday", places: 1))
    }

    private func press(_ scheduler: PushScheduler, _ themeId: String) async -> [TriggerProgress] {
        var steps: [TriggerProgress] = []
        for await step in await scheduler.tryTheme(themeId) { steps.append(step) }
        return steps
    }

    private func repeatMeta(_ index: Int = 0) throws -> [String: Any] {
        let data = try XCTUnwrap(client.repeatMetas.dropFirst(index).first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Round 2: ten candidates, one a day, 336 px and bare; the names to compare with.
    private func assertRoundTwoSentTen() throws {
        let request = try XCTUnwrap(rounds.roundTwoRequests.first)
        XCTAssertEqual(rounds.roundTwoRequests.count, 1)
        XCTAssertEqual(request.theme, RoundTwoRequest.Theme(name: "Dinner", noun: "dinner", samePart: "home at dusk"))
        XCTAssertEqual(request.photos.map(\.n), Array(1...10))
        XCTAssertEqual(request.pushed, [])
        XCTAssertEqual(request.blocked, ["Scale"])
        let images = try XCTUnwrap(rounds.roundTwoImages.first)
        XCTAssertEqual(images.map(\.n), Array(1...10))
        for image in images {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(image.jpeg as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary], "no coordinates")
            let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
            let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
            XCTAssertEqual(max(width, height), 336)
        }
        let logged = roundLog.load()
        XCTAssertEqual(logged.map(\.kind), ["round2"])
        XCTAssertEqual(logged.first?.themeId, "big")
    }

    /// The repeat compose: seven photos by date, P1...
    private func assertSevenComposed() throws {
        XCTAssertEqual(client.repeatMetas.count, 1)
        let meta = try repeatMeta()
        XCTAssertEqual(meta["mode"] as? String, "repeat")
        let theme = try XCTUnwrap(meta["theme"] as? [String: Any])
        XCTAssertEqual(theme["id"] as? String, "big")
        XCTAssertEqual(theme["name"] as? String, "Dinner")
        let photos = try XCTUnwrap(meta["photos"] as? [[String: Any]])
        XCTAssertEqual(photos.compactMap { $0["id"] as? String }, (1...7).map { "P\($0)" })
        XCTAssertEqual(client.lastPhotoNumbers, (1...7).map { "P\($0)" })
        let times = photos.compactMap { $0["taken_at"] as? String }
        XCTAssertEqual(times, times.sorted(), "by date")
        XCTAssertTrue(times.allSatisfy { $0.hasSuffix("-05:00") }, "local time with the offset: \(times)")
    }

    /// The debug push: 10 s out, marked repeat, never pushed.
    private func assertDebugRow(of ids: [String]) throws {
        XCTAssertEqual(notifier.scheduledAt, [nil], "10 s out")
        let entry = try XCTUnwrap(ledger.load().first)
        XCTAssertEqual(ledger.load().count, 1)
        XCTAssertTrue(entry.isDebug)
        XCTAssertEqual(entry.mode, "repeat")
        XCTAssertEqual(entry.themeId, "big")
        XCTAssertEqual(entry.themeName, "Dinner")
        XCTAssertEqual(entry.roundUsages, [FakeRoundClient.usage])
        XCTAssertEqual(entry.roundTwoTries, [])
        XCTAssertEqual(entry.bucket, .other)
        XCTAssertEqual(entry.scheduledFor, clock.now.addingTimeInterval(PushScheduler.debugDelay))
        XCTAssertEqual(entry.identifier, PushIdentifier.make(entry.pushId))
        XCTAssertEqual(entry.photoIds.count, 7)
        XCTAssertTrue(Set(entry.photoIds).isSubset(of: ids))
        XCTAssertTrue(entry.photoIds.contains("t-19") && entry.photoIds.contains("t-10"), "earliest and latest")
        let record = try XCTUnwrap(records.load(entry.pushId))
        XCTAssertEqual(record.isDebug, true)
        XCTAssertEqual(record.mode, "repeat")
        XCTAssertEqual(record.themeId, "big")
        XCTAssertEqual(record.themeName, "Dinner")
        XCTAssertEqual(record.roundUsages, [FakeRoundClient.usage])
        XCTAssertEqual(record.bucketId, .other)
        XCTAssertEqual((1...7).compactMap { record.photoIds["P\($0)"] }, entry.photoIds.sorted {
            Int($0.dropFirst(2))! > Int($1.dropFirst(2))!
        }, "P1... in date order")
    }
}
