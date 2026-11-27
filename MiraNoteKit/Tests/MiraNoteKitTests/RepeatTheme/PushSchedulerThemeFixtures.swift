import XCTest
@testable import MiraNoteKit

/// The scheduler test case with a fake round client and the theme fixtures
/// shared by the "test-push this theme" tests.
class PushSchedulerThemeCase: PushSchedulerTestCase {
    var rounds: FakeRoundClient!
    static let center = [Float](repeating: 0, count: 8).enumerated().map { $0.offset == 0 ? 1 : $0.element }

    override func setUpWithError() throws {
        try super.setUpWithError()
        rounds = FakeRoundClient()
    }
}

extension PushSchedulerThemeCase {
    var themeLibrary: ThemeLibrary { ThemeLibrary(file: folder.appendingPathComponent("themes/library.json")) }
    var themePhotos: ThemePhotoStore { ThemePhotoStore(directory: folder.appendingPathComponent("themes/p")) }
    var roundLog: RoundLog { RoundLog(file: folder.appendingPathComponent("themes/rounds.json")) }

    /// A large JPEG with GPS: what a round image is made from.
    static let bigJPEG: Data = {
        guard let data = try? ComposeMetaTests.jpegWithGPS(width: 1200, height: 900) else { fatalError("no JPEG") }
        return data
    }()

    func engine() -> ThemeEngine {
        let clock = self.clock!
        let zone = self.zone!
        return ThemeEngine(ThemeDependencies(
            library: library, analyzer: ThemeFakeAnalyzer(),
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), photos: themePhotos,
            themes: themeLibrary, rounds: roundLog,
            window: ThemeWindowStore(file: folder.appendingPathComponent("themes/window.json")),
            runs: ThemeRunLog(file: folder.appendingPathComponent("themes/runs.json")), client: rounds,
            imageData: { _ in Self.bigJPEG }, now: { clock.now }, calendar: zone.calendar,
            cooldown: ThemeAskCooldownStore(file: folder.appendingPathComponent("themes/failed-asks.json"))))
    }

    func scheduler() -> PushScheduler { makeScheduler(themeEngine: engine()) }

    /// 19:00 in Chicago, `days` before the test's start.
    func evening(_ days: Int) -> Date { start.addingTimeInterval(-Double(days) * 86_400 + 8 * 3600) }

    /// One photo `<prefix>-<day>` a day at 19:00, in the library, with a theme record near the look.
    @discardableResult
    func seed(_ prefix: String, days: [Int], label: (String, Float) = ("food", 0.9),
              aesthetics: Double? = nil, location: GeoPoint? = nil) throws -> [String] {
        var records: [ThemePhoto] = []
        for day in days {
            let id = "\(prefix)-\(day)"
            library.assetsList.append(LibraryAsset(id: id, takenAt: evening(day), location: location,
                                                   isFavorite: day == days[0], isEdited: false, isScreenshot: false,
                                                   isHidden: false, isVideo: false,
                                                   originalFilename: "IMG_\(day).HEIC", burstId: nil))
            var raw = Self.center
            raw[1 + day % 7] = 0.3
            records.append(ThemePhoto(id: id, takenAt: evening(day), location: location,
                                      labels: [LabelScore(id: label.0, confidence: label.1)],
                                      aesthetics: aesthetics ?? 0.5 + Double(day % 3) / 10, faces: 0, isTheme: true,
                                      print: ThemePhoto.normalized(raw), printRevision: 1))
        }
        try themePhotos.upsert(records, calendar: zone.calendar)
        return records.map(\.id)
    }

    func big(_ id: String = "big", name: String = "Dinner", members: [String],
             status: ThemeStatus = .active) -> ThemeRow {
        ThemeRow(id: id, kind: .big, parentId: nil, name: name, noun: "dinner", samePart: "home at dusk",
                 split: "A", status: status, center: Self.center, rule: nil, members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil, where: nil)
    }

    func small(_ id: String, name: String, members: [String]) -> ThemeRow {
        ThemeRow(id: id, kind: .small, parentId: "big", name: name, noun: "soup", samePart: "a bowl", split: "A",
                 status: .active, center: nil, rule: .content(evidence: ["soup"]), members: members,
                 lastAskedCount: members.count, flagged: false, followRatio: nil,
                 where: WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20,
                                   weekpart: "weekday", places: 1))
    }

    func press(_ scheduler: PushScheduler, _ themeId: String) async -> [TriggerProgress] {
        var steps: [TriggerProgress] = []
        for await step in await scheduler.tryTheme(themeId) { steps.append(step) }
        return steps
    }

    func repeatMeta(_ index: Int = 0) throws -> [String: Any] {
        let data = try XCTUnwrap(client.repeatMetas.dropFirst(index).first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
