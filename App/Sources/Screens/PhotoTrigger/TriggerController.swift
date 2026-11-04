import MiraNoteKit
import Photos
import SwiftUI
import UIKit
import UserNotifications

/// The photo trigger as the app holds it for its lifetime: the
/// `PushScheduler` that plans the pushes whenever the app comes to the
/// front, the steps of the current debug press, the fake-AI switch, and
/// where pushes and photos are read back from.
@MainActor
@Observable
final class TriggerController {
    /// What the last "Preview the scheduled push" press said, when it is not
    /// a progress step.
    enum Notice: Equatable {
        case nothingScheduled
        case notificationsOff
        case previewSent(slotDay: String)
    }

    /// The current press's steps, oldest first.
    private(set) var steps: [TriggerProgress] = []
    private(set) var notice: Notice?
    private(set) var isRunning = false
    var fakeAI: Bool {
        didSet { AppSettings.storeDefaults.set(fakeAI, forKey: Self.fakeAIKey) }
    }

    let photos: TriggerPhotoProviding
    let records: PushRecordStore
    let scheduler: PushScheduler
    @ObservationIgnored private let permissions: TriggerPermissions
    /// False under `-TRIGGER-NO-SCHEDULE` (UI tests of the debug buttons):
    /// coming to the front plans nothing, so every group is "outside".
    @ObservationIgnored private let schedulesAutomatically: Bool
    @ObservationIgnored private let fakeAIFlag = FakeAIFlag()
    @ObservationIgnored private var background: BackgroundTime?

    static let fakeAIKey = "photoTrigger.fakeAI"

    init(photos: TriggerPhotoProviding, records: PushRecordStore, dependencies: (FakeAIFlag) -> SchedulerDependencies,
         permissions: TriggerPermissions, schedulesAutomatically: Bool = true, fakeAI: Bool) {
        self.schedulesAutomatically = schedulesAutomatically
        self.photos = photos
        self.records = records
        self.fakeAI = fakeAI
        self.permissions = permissions
        fakeAIFlag.value = fakeAI
        scheduler = PushScheduler(dependencies(fakeAIFlag))
        Task {
            // The zone is read afresh at each run; this drops the system's
            // cached one so a trip across zones shows up on the next return.
            for await _ in NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange) {
                NSTimeZone.resetSystemTimeZone()
            }
        }
    }

    // MARK: Lifecycle

    /// The app is in front (also its first appearance): first launch asks
    /// Photos, then notifications -- each only while undecided -- and the
    /// scheduler plans the nights, inside a stretch of background time so a
    /// quick switch away does not freeze it half-way.
    func sceneBecameActive() async {
        guard schedulesAutomatically else { return }
        await permissions.askFirstLaunch()
        let time = BackgroundTime()
        background = time
        time.begin { [scheduler] in await scheduler.backgroundTimeExpired() }
        await scheduler.appBecameActive()
        time.end()
    }

    func sceneEnteredBackground() {
        Task { await scheduler.appEnteredBackground() }
    }

    /// A tapped push: the ledger learns it was opened before the story opens.
    func opened(_ pushId: String) async {
        await scheduler.markOpened(pushId)
    }

    /// The story menu's choice: the scheduler records it, takes back what it
    /// rules out and replans at once.
    func menu(_ action: MenuAction, pushId: String) {
        Task { await scheduler.menu(action, pushId: pushId) }
    }

    /// The story reached its ending.
    func storyFinished(_ pushId: String) {
        Task { await scheduler.markStoryFinished(pushId) }
    }

    /// The writer made a page from this push (kept the draft).
    func madePage(_ pushId: String) {
        Task { await scheduler.markMadePage(pushId) }
    }

    // MARK: Debug entry

    private func record(_ step: TriggerProgress) {
        if step == .preparing { steps = [] }
        // One counting line, not one per photo.
        if case .analyzing = step, case .analyzing = steps.last {
            steps[steps.count - 1] = step
        } else {
            steps.append(step)
        }
    }

    /// "Preview the scheduled push": a copy of the next scheduled push in 10 s.
    func previewNext() {
        guard !isRunning else { return }
        isRunning = true
        steps = []
        notice = nil
        Task {
            switch await scheduler.previewNext() {
            case .scheduled(let day): notice = .previewSent(slotDay: day)
            case .nothingScheduled: notice = .nothingScheduled
            case .notificationsOff: steps = [.failed(.notificationsOff)]
            }
            isRunning = false
        }
    }

    /// "Try a group outside the schedule". The press asks iOS for background
    /// time, so leaving the app right after pressing does not freeze it at
    /// once; past that time the job is picked up on return (ComposeSession).
    func tryOutside() {
        guard !isRunning else { return }
        isRunning = true
        notice = nil
        fakeAIFlag.value = fakeAI
        let time = BackgroundTime()
        time.begin(onExpire: nil)
        Task {
            for await step in await scheduler.tryOutside() { record(step) }
            isRunning = false
            time.end()
        }
    }

    /// Keeps the last run's grouping on the phone (local only) for checking.
    @Sendable nonisolated static func saveGroupingReport(_ data: Data) {
        let file = GroupingReport.defaultFile
        try? PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try? data.write(to: file, options: .atomic)
    }

    /// The one controller of this launch: made once, so the -UITEST-TRIGGER
    /// folder is emptied once.
    static let shared = make()

    /// The app's one controller: PhotoKit, Vision, Apple's geocoder and the
    /// photo-collections backend -- or, under `-UITEST-TRIGGER`, the
    /// synthetic library and a scripted backend.
    private static func make() -> TriggerController {
        let fakeAI = AppSettings.storeDefaults.bool(forKey: fakeAIKey)
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
            permissions: .live, fakeAI: fakeAI
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
            fakeAI: arguments.contains("-TRIGGER-FAKE-AI")
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

/// The first-launch prompts, in order: Photos, then notifications, each only
/// while the system has not been asked (handoff G5).
struct TriggerPermissions: Sendable {
    var photosUndecided: @Sendable () -> Bool
    var askPhotos: @Sendable () async -> Void
    var notificationsUndecided: @Sendable () async -> Bool
    var askNotifications: @Sendable () async -> Void

    func askFirstLaunch() async {
        if photosUndecided() { await askPhotos() }
        if await notificationsUndecided() { await askNotifications() }
    }

    static let live = TriggerPermissions(
        photosUndecided: { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined },
        askPhotos: { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) },
        notificationsUndecided: {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
        },
        askNotifications: {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    )

    /// Nothing is asked (UI tests that keep their Home as it was).
    static let none = TriggerPermissions(
        photosUndecided: { false }, askPhotos: {}, notificationsUndecided: { false }, askNotifications: {}
    )
}

/// One stretch of background time, ended once: when the work is over or
/// when iOS says the time is up, whichever comes first.
@MainActor
private final class BackgroundTime {
    private var task: UIBackgroundTaskIdentifier = .invalid

    /// `onExpire` runs first when iOS says the time is up.
    func begin(onExpire: (@Sendable () async -> Void)?) {
        task = UIApplication.shared.beginBackgroundTask(withName: "photo-trigger") { [weak self] in
            // iOS calls this on the main thread.
            MainActor.assumeIsolated {
                guard let onExpire else { return self?.end() ?? () }
                // Ended after the scheduler has noted what was left out.
                Task { @MainActor in
                    await onExpire()
                    self?.end()
                }
            }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

/// The switch as the run reads it, off the main actor.
final class FakeAIFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The trigger's content words (push, question, button, bucket) are
/// Chinese whatever the app language (handoff 7.0): read from the built
/// zh-Hans table, falling back to the key.
enum TriggerContent {
    private static let table: Bundle? = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init)

    @Sendable static func zh(_ key: String) -> String {
        table?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }
}
