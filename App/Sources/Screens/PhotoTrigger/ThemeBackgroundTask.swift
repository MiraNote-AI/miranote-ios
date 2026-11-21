import BackgroundTasks
import MiraNoteKit

/// BGTaskScheduler, as far as the theme task needs it (a fake in tests).
protocol ThemeTaskScheduling: Sendable {
    /// False when iOS refuses (the identifier is not in Info.plist).
    func register(_ identifier: String, launchHandler: @escaping (ThemeProcessingTask) -> Void) -> Bool
    func submit(_ request: BGTaskRequest) throws
    /// Takes back a request not run yet.
    func cancel(_ identifier: String)
}

/// The task iOS hands the app when it wakes it, as a run uses it.
protocol ThemeProcessingTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: ThemeProcessingTask {}

/// The repeat-theme finder, as the app drives it.
protocol ThemeRunning: Sendable {
    func run(trigger: ThemeTrigger, deadline: Date?) async -> ThemeRunReport
    func stopEarly()
}

extension ThemeEngine: ThemeRunning {}

struct LiveThemeTaskScheduler: ThemeTaskScheduling {
    func register(_ identifier: String, launchHandler: @escaping (ThemeProcessingTask) -> Void) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { launchHandler($0) }
    }

    func submit(_ request: BGTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel(_ identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

/// Finds repeat themes while the phone charges (spec section 4): a
/// `BGProcessingTask` that iOS runs when the phone is on power and online,
/// asked for again after every run, and only while the install's gates are
/// open. Its handler is registered at every launch (a request left from an
/// earlier launch is delivered only to a launch that registered one); a
/// run starts only once the gates are open, and stops when iOS takes the
/// time back.
struct ThemeBackgroundTask {
    static let identifier = "app.miranote.photo-trigger.themes"
    /// A processing task is given no known expiry time: a run asks for this
    /// long at most (the engine keeps `clusterReserve` of it to cluster and
    /// ask), and stops sooner if iOS expires the task.
    static let budget: TimeInterval = 4 * 60

    static let live = ThemeBackgroundTask(scheduler: LiveThemeTaskScheduler())

    let scheduler: ThemeTaskScheduling
    var now: @Sendable () -> Date = { Date() }

    /// At every launch, before the app finishes launching (iOS requires
    /// it, and raises for a pending request with no handler). Registering
    /// asks for no run.
    func register(handler: @escaping (ThemeProcessingTask) -> Void) {
        _ = scheduler.register(Self.identifier, launchHandler: handler)
    }

    /// The next run: on power and online, whenever iOS likes. Replaces one
    /// already asked for. Refusals are quiet: the simulator, Background App
    /// Refresh off; the next foreground asks again.
    func submit() {
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        try? scheduler.submit(request)
    }

    /// One woken run: until `budget` from now, or until iOS says the time
    /// is up -- then the engine stops early (what it saved stays, the next
    /// run goes on) and the task is completed at once, as iOS requires.
    /// Gates closed (the switch went off since the request): nothing runs
    /// and a request still pending is taken back. The report, or nil when
    /// nothing ran (also when the task expired while the gates resolved).
    @discardableResult
    func run(_ task: ThemeProcessingTask, engine: ThemeRunning,
             gatesOpen: () async -> Bool) async -> ThemeRunReport? {
        let deadline = now().addingTimeInterval(Self.budget)
        let completion = TaskCompletion(task)
        task.expirationHandler = { [self] in
            engine.stopEarly()
            submit()
            completion.finish(success: false)
        }
        guard await gatesOpen() else {
            scheduler.cancel(Self.identifier)
            completion.finish(success: true)
            return nil
        }
        guard !completion.isFinished else { return nil }
        let report = await engine.run(trigger: .background, deadline: deadline)
        if completion.finish(success: true) { submit() }
        return report
    }
}

/// Completes the task once: at the end of the run, or at its expiration,
/// whichever comes first (iOS calls the expiration handler on its own queue).
private final class TaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: ThemeProcessingTask?

    init(_ task: ThemeProcessingTask) {
        self.task = task
    }

    var isFinished: Bool { lock.withLock { task == nil } }

    /// False when the task was completed already.
    @discardableResult
    func finish(success: Bool) -> Bool {
        guard let task = lock.withLock({ () -> ThemeProcessingTask? in
            defer { self.task = nil }
            return self.task
        }) else { return false }
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        return true
    }
}
