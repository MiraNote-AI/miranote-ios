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
        return TriggerController(
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
                    fakeAI: { flag.value }, zh: TriggerContent.zh
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
