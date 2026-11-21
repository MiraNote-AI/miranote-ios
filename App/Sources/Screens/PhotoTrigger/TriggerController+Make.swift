import MiraNoteKit
import SwiftUI

/// How the app's one controller is made: live, or under `-UITEST-TRIGGER`
/// synthetic.
extension TriggerController {
    /// The one controller of this launch: made once, so the -UITEST-TRIGGER
    /// folder is emptied once.
    static let shared = make()

    /// The app's one controller: PhotoKit, Vision, Apple's geocoder and the
    /// photo-collections backend, with the repeat-theme finder -- or, under
    /// `-UITEST-TRIGGER`, the synthetic library and a scripted backend. The
    /// finder is built in every build but runs only behind the install's
    /// gates, as V1's scheduling does: after a gated foreground run, from
    /// the gated background task, or from the debug page's test-push.
    private static func make() -> TriggerController {
        let fakeAI = AppSettings.storeDefaults.bool(forKey: fakeAIKey)
        let optedIn = AppSettings.storeDefaults.bool(forKey: optedInKey)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST-TRIGGER") { return makeSynthetic() }
        #endif
        let reader = PhotoLibraryReader()
        let analyzer = PhotoAnalyzer(photos: reader)
        let clock = debugClock(ProcessInfo.processInfo.arguments)
        let themePhotos = ThemePhotoStore(directory: ThemePhotoStore.defaultDirectory)
        let engine = makeThemeEngine(reader: reader, analyzer: analyzer, photos: themePhotos, clock: clock)
        return TriggerController(
            photos: reader, records: PushRecordStore(directory: PushRecordStore.defaultDirectory),
            dependencies: { flag in
                var deps = SchedulerDependencies(
                    library: reader, analyzer: analyzer, places: PlaceNamer(),
                    client: LiveComposeClient(), notifications: LivePushNotificationCenter(photos: reader),
                    calendar: { Calendar.autoupdatingCurrent },
                    fakeAI: { flag.value }, zh: TriggerContent.zh, groupingReport: saveGroupingReport,
                    themes: themePhotos, themeEngine: engine
                )
                if let clock { deps.now = clock }
                return deps
            },
            permissions: .live, fakeAI: fakeAI, optedIn: optedIn
        )
    }

    /// The repeat-theme finder over the live library and backend. On the
    /// simulator the checkup gives no theme vision (its prints are all
    /// alike), so no theme record is kept there: the engine leaves those
    /// photos out for the rest of the launch and finds no piles.
    private static func makeThemeEngine(reader: PhotoLibraryReader, analyzer: PhotoAnalyzer,
                                        photos: ThemePhotoStore, clock: (@Sendable () -> Date)?) -> ThemeEngine {
        ThemeEngine(ThemeDependencies(
            library: reader, analyzer: analyzer,
            analyses: AnalysisStore(directory: AnalysisStore.defaultDirectory), photos: photos,
            themes: ThemeLibrary(file: ThemeLibrary.defaultFile), rounds: RoundLog(file: RoundLog.defaultFile),
            window: ThemeWindowStore(file: ThemeWindowStore.defaultFile),
            runs: ThemeRunLog(file: ThemeRunLog.defaultFile), client: LiveThemeRoundClient(),
            imageData: { await reader.uploadData(for: $0) }, now: clock ?? { Date() },
            calendar: .autoupdatingCurrent
        ))
    }

    #if DEBUG
    /// `-UITEST-TRIGGER`: the synthetic library, a scripted backend and
    /// notifications that never reach the system.
    private static func makeSynthetic() -> TriggerController {
        let arguments = ProcessInfo.processInfo.arguments
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestTrigger", isDirectory: true)
        if !arguments.contains("-KEEP_SETTINGS") { try? FileManager.default.removeItem(at: folder) }
        let synthetic = SyntheticTriggerLibrary()
        let records = PushRecordStore(directory: folder.appendingPathComponent("pushes"))
        let clock = debugClock(arguments)
        let themePhotos = ThemePhotoStore(directory: folder.appendingPathComponent("themes/photos"))
        let engine = syntheticThemeEngine(library: synthetic, folder: folder, photos: themePhotos, clock: clock)
        let controller = TriggerController(
            photos: synthetic, records: records,
            dependencies: { flag in
                var deps = SchedulerDependencies(
                    library: synthetic, analyzer: synthetic, places: UITestPlaces(), client: UITestComposeClient(),
                    notifications: UITestNotifier(),
                    analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")),
                    records: records,
                    ledger: PushLedgerStore(file: folder.appendingPathComponent("ledger.json")),
                    preferences: PushPreferencesStore(file: folder.appendingPathComponent("preferences.json")),
                    cache: AIResultCache(file: folder.appendingPathComponent("cache.json")),
                    log: ScheduleLogStore(file: folder.appendingPathComponent("log.json")),
                    state: SchedulerStateStore(file: folder.appendingPathComponent("state.json")),
                    lastRun: LastRunStore(file: folder.appendingPathComponent("last-run.json")),
                    calendar: { Calendar.autoupdatingCurrent },
                    fakeAI: { flag.value }, zh: TriggerContent.zh,
                    themes: themePhotos, themeEngine: engine
                )
                if let clock { deps.now = clock }
                return deps
            },
            // The real prompts only when a test is about them.
            permissions: arguments.contains("-TRIGGER-REAL-PERMISSIONS") ? .live : .none,
            schedulesAutomatically: !arguments.contains("-TRIGGER-NO-SCHEDULE"),
            fakeAI: arguments.contains("-TRIGGER-FAKE-AI"),
            optedIn: AppSettings.storeDefaults.bool(forKey: optedInKey)
        )
        if arguments.contains("-TRIGGER-TRY-THEME") { Task { await controller.tryFirstTheme(engine) } }
        if arguments.contains("-TRIGGER-FIND-THEMES") {
            let library = ThemeLibrary(file: folder.appendingPathComponent("themes/library.json"))
            Task { await findThemes(engine, flag: arguments.contains("-TRIGGER-FLAG-THEME") ? library : nil) }
        }
        return controller
    }

    /// `-TRIGGER-FIND-THEMES` (UI tests of the Themes page): the themes are
    /// found, then claimed on a second run as the next night's would be, so
    /// each follows its pile. Nothing is pushed. With `-TRIGGER-FLAG-THEME`
    /// the first big theme then reads as followed at 40% (`flag`, its
    /// library), as one half gone from its pile would: the synthetic piles
    /// hold all of a theme's photos, and two piles cannot give a share under
    /// a half.
    private static func findThemes(_ engine: ThemeEngine, flag: ThemeLibrary?) async {
        _ = await engine.run(trigger: .foreground, deadline: nil)
        _ = await engine.run(trigger: .foreground, deadline: nil)
        guard let flag else { return }
        var rows = flag.load()
        guard let index = rows.firstIndex(where: { $0.kind == .big }) else { return }
        rows[index].followRatio = 0.4
        rows[index].flagged = true
        try? flag.save(rows)
    }

    /// `-TRIGGER-TRY-THEME` (UI tests of repeat pushes): the themes are found
    /// on the synthetic library, then the first one in the library is
    /// test-pushed, as the debug page's button would -- one press per launch.
    private func tryFirstTheme(_ engine: ThemeEngine) async {
        _ = await engine.run(trigger: .foreground, deadline: nil)
        guard let first = await engine.snapshot().themes.first else { return }
        tryTheme(first.id)
    }

    /// The repeat-theme finder over the synthetic library (two themes with
    /// made-up prints), the scripted round client and stores under the
    /// test's folder.
    private static func syntheticThemeEngine(library: SyntheticTriggerLibrary, folder: URL, photos: ThemePhotoStore,
                                             clock: (@Sendable () -> Date)?) -> ThemeEngine {
        let themes = folder.appendingPathComponent("themes", isDirectory: true)
        return ThemeEngine(ThemeDependencies(
            library: library, analyzer: library,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")), photos: photos,
            themes: ThemeLibrary(file: themes.appendingPathComponent("library.json")),
            rounds: RoundLog(file: themes.appendingPathComponent("rounds.json")),
            window: ThemeWindowStore(file: themes.appendingPathComponent("window.json")),
            runs: ThemeRunLog(file: themes.appendingPathComponent("runs.json")), client: UITestThemeRoundClient(),
            imageData: { await library.uploadData(for: $0) }, now: clock ?? { Date() },
            calendar: .autoupdatingCurrent
        ))
    }
    #endif

    /// `-TRIGGER-NOW <ISO8601>` (DEBUG): the scheduler's clock starts at that
    /// moment and runs on in real time.
    private static func debugClock(_ arguments: [String]) -> (@Sendable () -> Date)? {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-TRIGGER-NOW"), arguments.indices.contains(index + 1),
              let base = ISO8601DateFormatter().date(from: arguments[index + 1]) else { return nil }
        let launched = Date()
        return { base.addingTimeInterval(Date().timeIntervalSince(launched)) }
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// `-UITEST-TRIGGER`: the judge rounds answered by script, as a valid
/// reply to any pile. Round 1: the eight-day pile (theme 1) is named and
/// split by time and place (B, its first offered group); any other pile is
/// named and left whole (`none`). Round 2: every photo belongs.
struct UITestThemeRoundClient: ThemeRoundClient {
    private static let usage = RoundUsage(promptTokens: 1978, completionTokens: 248, costCny: 0.00059,
                                          model: "qwen3.7-flash")

    func roundOne(_ request: RoundOneRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        let dinner = request.dayCount >= 7
        var answer: [String: Any] = [
            // Home dinner / the morning light outside the window.
            "pile_name": dinner ? "\u{5BB6}\u{91CC}\u{7684}\u{665A}\u{996D}"
                : "\u{7A97}\u{5916}\u{7684}\u{6668}\u{5149}",
            "pile_noun": dinner ? "\u{665A}\u{996D}" : "\u{6668}\u{5149}",
            "sensitive": false, "drop_groups": [String](), "not_in_pile": [Int](), "two_kinds": false
        ]
        if dinner, let first = request.splitB.first {
            answer["chosen"] = "B"
            answer["groups"] = [[
                "from": [first.id], "name": "\u{5DE5}\u{4F5C}\u{65E5}\u{665A}\u{996D}",
                "noun": "\u{665A}\u{996D}", "same_part": "\u{540C}\u{4E00}\u{5F20}\u{9910}\u{684C}"
            ] as [String: Any]]
        } else {
            answer["chosen"] = "none"
            answer["groups"] = [[String: Any]]()
        }
        let lines = Dictionary(uniqueKeysWithValues: (request.splitA + request.splitB).map {
            ($0.id, "\u{4E3B}\u{8981}\u{5728}\u{540C}\u{4E00}\u{4E2A}\u{5730}\u{65B9}")
        })
        return RoundReply(reply: try Self.json(answer), where: lines, usage: Self.usage)
    }

    func roundTwo(_ request: RoundTwoRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        let photos = request.photos.map {
            ["id": $0.n, "belongs": true, "dup_of": NSNull(), "poor": false, "sensitive": false] as [String: Any]
        }
        let answer: [String: Any] = ["photos": photos, "similar_to": [Any]()]
        return RoundReply(reply: try Self.json(answer), where: [:], usage: Self.usage)
    }

    func shorten(_ items: [ShortenItem]) async throws -> RoundReply {
        let echoed = items.map { ["key": $0.key, "name": $0.name, "same_part": $0.samePart] }
        return RoundReply(reply: try Self.json(["items": echoed]), where: [:], usage: Self.usage)
    }

    private static func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
#endif
