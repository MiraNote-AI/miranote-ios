import MiraNoteKit
import SwiftUI
import UIKit

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
    /// Read by the scheduler from its next step on. Turned off, the pushes
    /// the fake AI wrote are composed again with the real AI.
    var fakeAI: Bool {
        didSet {
            AppSettings.storeDefaults.set(fakeAI, forKey: Self.fakeAIKey)
            fakeAIFlag.value = fakeAI
            if oldValue, !fakeAI { fakeAITurnedOff() }
        }
    }
    /// The Settings switch of a TestFlight install
    /// (`InstallSource.Gates.offersOptIn`), off until the tester turns it
    /// on. On, the gates open -- the lifecycle then asks and plans -- and
    /// the ending's fonts start downloading; off, every pending push is
    /// taken back and a run in flight stops writing.
    var optedIn: Bool {
        didSet {
            guard optedIn != oldValue else { return }
            AppSettings.storeDefaults.set(optedIn, forKey: Self.optedInKey)
            optInChanged()
        }
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
    /// What this install may do (InstallSource), resolved once per launch;
    /// nil until HomeFlow asks.
    @ObservationIgnored private var gates: Task<InstallSource.Gates, Never>?
    /// Bumped at each scene-phase change the scheduler hears of: its hops
    /// may land out of order, and it ignores one older than the last.
    @ObservationIgnored private var phaseSequence = 0
    /// The first-launch prompts while they are up: each sends the scene
    /// inactive and back, and that return waits for them instead of planning
    /// before the answers (notifications would still read as off).
    @ObservationIgnored private var asking: Task<Void, Never>?
    /// Starts the ending's font downloads.
    @ObservationIgnored private let prefetchFonts: @Sendable () -> Void
    /// The install's gates once resolved (`gates` is the task resolving them).
    @ObservationIgnored private var resolved: InstallSource.Gates?
    /// What the last turn of the switch set going, after the turns before it
    /// (tests wait for it).
    @ObservationIgnored private(set) var optInChange: Task<Void, Never>?

    static let fakeAIKey = "photoTrigger.fakeAI"
    static let optedInKey = "photoTrigger.optedIn"

    init(photos: TriggerPhotoProviding, records: PushRecordStore, dependencies: (FakeAIFlag) -> SchedulerDependencies,
         permissions: TriggerPermissions, schedulesAutomatically: Bool = true, fakeAI: Bool, optedIn: Bool = false,
         prefetchFonts: @escaping @Sendable () -> Void = DetailFont.prefetch) {
        self.schedulesAutomatically = schedulesAutomatically
        self.prefetchFonts = prefetchFonts
        self.photos = photos
        self.records = records
        self.fakeAI = fakeAI
        self.optedIn = optedIn
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
        let sequence = nextPhase()
        await askFirstLaunch()
        // The scheduler has heard the latest turn of the switch; off while
        // the prompts were up, nothing is planned.
        await optInChange?.value
        if await openGates()?.schedulesAutomatically == false { return }
        let time = BackgroundTime()
        background = time
        time.begin { [scheduler] in await scheduler.backgroundTimeExpired() }
        await scheduler.appBecameActive(sequence: sequence)
        time.end()
    }

    func sceneEnteredBackground() {
        let sequence = nextPhase()
        Task { [scheduler] in await scheduler.appEnteredBackground(sequence: sequence) }
    }

    private func askFirstLaunch() async {
        if let asking { return await asking.value }
        let task = Task { [permissions] in await permissions.askFirstLaunch() }
        asking = task
        await task.value
        asking = nil
    }

    private func nextPhase() -> Int {
        phaseSequence += 1
        return phaseSequence
    }

    /// A tapped push: the ledger learns it was opened before the story opens.
    func opened(_ pushId: String) async {
        await scheduler.markOpened(pushId)
    }

    /// The install's gates, resolved by `resolve` the first time and the same
    /// answer after (HomeFlow may be made again). The Settings switch is not
    /// read in: see `applying(optedIn:)`. A definite App Store install takes
    /// back the pushes a TestFlight build left pending: each could only open
    /// a story whose menu leads to a run (decision 8); so does a TestFlight
    /// install whose switch is off, and either turns the scheduler off. The
    /// ending's fonts start downloading only where the trigger can show.
    func resolveGates(_ resolve: @escaping @Sendable () async -> InstallSource.Gates) async
        -> InstallSource.Gates {
        if let gates { return await gates.value }
        let task = Task { [scheduler] in
            let gates = await resolve()
            if gates.isAppStore { await scheduler.turnOff(.appStore) }
            return gates
        }
        gates = task
        let answer = await task.value
        // From here a turn of the switch acts on its own (`optInChanged`).
        resolved = answer
        if answer.applying(optedIn: optedIn).triggerCanShow {
            prefetchFonts()
        } else if answer.offersOptIn {
            let previous = optInChange
            optInChange = Task { [scheduler] in
                await previous?.value
                await scheduler.turnOff(.optedOut)
            }
            await optInChange?.value
        }
        return answer
    }

    /// The gates with the Settings switch read in; nil until resolved.
    private func openGates() async -> InstallSource.Gates? {
        guard let gates else { return nil }
        return await gates.value.applying(optedIn: optedIn)
    }

    /// The switch turned: on, the scheduler may run again and the fonts
    /// start downloading; off, the scheduler is turned off (`turnOff`). Each
    /// turn reaches the scheduler after the one before. Only a TestFlight
    /// install has the switch; gates not resolved yet, `resolveGates` acts
    /// on the switch as it then is.
    private func optInChanged() {
        guard let resolved, resolved.offersOptIn else { return }
        let on = optedIn
        if on { prefetchFonts() }
        let previous = optInChange
        optInChange = Task { [scheduler] in
            await previous?.value
            if on {
                await scheduler.turnOn()
            } else {
                await scheduler.turnOff(.optedOut)
            }
        }
    }

    /// The story menu's choice: the scheduler records it, takes back what it
    /// rules out and -- only where this install may schedule automatically
    /// (decision 8) -- replans at once. Gates not resolved: no replan.
    @discardableResult
    func menu(_ action: MenuAction, pushId: String) -> Task<Void, Never> {
        Task { [scheduler] in
            let replan = await self.openGates()?.schedulesAutomatically ?? false
            await scheduler.menu(action, pushId: pushId, replan: replan)
        }
    }

    /// The switch went off with the app open: the scheduler takes back what
    /// the fake AI wrote and runs at once -- only where this install
    /// schedules automatically (decision 8), as coming to the front does.
    private func fakeAITurnedOff() {
        guard schedulesAutomatically else { return }
        Task { [scheduler] in
            guard await self.openGates()?.schedulesAutomatically ?? false else { return }
            await scheduler.fakeAITurnedOff()
        }
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
}

/// One stretch of background time, ended once: when the work is over or
/// when iOS says the time is up, whichever comes first.
@MainActor
private final class BackgroundTime {
    private var task: UIBackgroundTaskIdentifier = .invalid

    /// When iOS says the time is up, `onExpire` gets at most
    /// `BoundedWait.expiryGrace` and the task is ended inside the handler
    /// whatever it did: iOS kills an app that overruns. If `onExpire` is
    /// slower it goes on after (or on the next wake).
    func begin(onExpire: (@Sendable () async -> Void)?) {
        task = UIApplication.shared.beginBackgroundTask(withName: "photo-trigger") { [weak self] in
            // iOS calls this on the main thread.
            MainActor.assumeIsolated {
                if let onExpire { BoundedWait.run(atMost: BoundedWait.expiryGrace, onExpire) }
                self?.end()
            }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
