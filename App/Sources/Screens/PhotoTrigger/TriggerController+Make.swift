import MiraNoteKit
import SwiftUI

/// How the app's one controller is made: live, or under `-UITEST-TRIGGER`
/// synthetic.
extension TriggerController {
    /// The one controller of this launch: made once, so the -UITEST-TRIGGER
    /// folder is emptied once.
    static let shared = make()

    /// The app's one controller: PhotoKit, Vision, Apple's geocoder and the
    /// photo-collections backend -- or, under `-UITEST-TRIGGER`, the
    /// synthetic library and a scripted backend.
    private static func make() -> TriggerController {
        let fakeAI = AppSettings.storeDefaults.bool(forKey: fakeAIKey)
        let optedIn = AppSettings.storeDefaults.bool(forKey: optedInKey)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST-TRIGGER") { return makeSynthetic() }
        #endif
        let reader = PhotoLibraryReader()
        let clock = debugClock(ProcessInfo.processInfo.arguments)
        return TriggerController(
            photos: reader, records: PushRecordStore(directory: PushRecordStore.defaultDirectory),
            dependencies: { flag in
                var deps = SchedulerDependencies(
                    library: reader, analyzer: PhotoAnalyzer(photos: reader), places: PlaceNamer(),
                    client: LiveComposeClient(), notifications: LivePushNotificationCenter(photos: reader),
                    calendar: { Calendar.autoupdatingCurrent },
                    fakeAI: { flag.value }, zh: TriggerContent.zh, groupingReport: saveGroupingReport
                )
                if let clock { deps.now = clock }
                return deps
            },
            permissions: .live, fakeAI: fakeAI, optedIn: optedIn
        )
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
