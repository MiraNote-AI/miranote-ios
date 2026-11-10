import MiraNoteKit
import XCTest
@testable import MiraNote

/// Handoff G5: the first launch asks Photos, then notifications, and plans
/// only after both answers -- even though each prompt sends the scene
/// inactive and back, which calls `sceneBecameActive` again meanwhile.
@MainActor
final class TriggerFirstLaunchTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testReturnWhileThePromptsAreUpWaitsForTheAnswers() async throws {
        let system = FakeSystem()
        let library = SyntheticTriggerLibrary()
        let records = PushRecordStore(directory: folder.appendingPathComponent("pushes"))
        let folder = self.folder!
        let log = ScheduleLogStore(file: folder.appendingPathComponent("log.json"))
        let controller = TriggerController(
            photos: library, records: records,
            dependencies: { flag in
                SchedulerDependencies(
                    library: library, analyzer: library, places: UITestPlaces(), client: UITestComposeClient(),
                    notifications: system,
                    analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")),
                    records: records,
                    ledger: PushLedgerStore(file: folder.appendingPathComponent("ledger.json")),
                    preferences: PushPreferencesStore(file: folder.appendingPathComponent("preferences.json")),
                    cache: AIResultCache(file: folder.appendingPathComponent("cache.json")),
                    log: log,
                    state: SchedulerStateStore(file: folder.appendingPathComponent("state.json")),
                    lastRun: LastRunStore(file: folder.appendingPathComponent("last-run.json")),
                    fakeAI: { flag.value }, zh: TriggerContent.zh)
            },
            permissions: system.permissions, fakeAI: true)

        let first = Task { await controller.sceneBecameActive() }
        try await system.waitForPrompt()
        // The Photos answer brings the scene back while the notification
        // prompt is about to go up.
        let second = Task { await controller.sceneBecameActive() }
        try await Task.sleep(nanoseconds: 300_000_000)
        system.answer()
        await first.value
        await second.value

        XCTAssertEqual(system.prompts, 1, "the prompts are asked once")
        let runs = log.runs()
        XCTAssertFalse(runs.isEmpty, "the nights are planned")
        XCTAssertTrue(runs.allSatisfy { $0.error == nil }, "no run before the answers: \(runs.map(\.error))")
    }
}

/// The system's prompts: the first ask stays up until `answer()`, which
/// allows both; an ask while one is up returns at once, unanswered, as
/// iOS does for a second request in flight.
private final class FakeSystem: PushNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var decided = false
    private var up: CheckedContinuation<Void, Never>?
    private var count = 0
    private var pendingSet: Set<String> = []

    var prompts: Int { lock.withLock { count } }

    var permissions: TriggerPermissions {
        TriggerPermissions(
            photosUndecided: { [self] in lock.withLock { !decided } },
            askPhotos: { [self] in await prompt() },
            notificationsUndecided: { [self] in lock.withLock { !decided } },
            askNotifications: { [self] in await prompt() })
    }

    private func prompt() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                guard up == nil, !decided else { return true }
                count += 1
                up = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func waitForPrompt() async throws {
        var tries = 0
        while lock.withLock({ up == nil }), tries < 200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            tries += 1
        }
        XCTAssertNotNil(lock.withLock { up }, "the first prompt went up")
    }

    func answer() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            decided = true
            defer { up = nil }
            return up
        }
        continuation?.resume()
    }

    func isAllowed() async -> Bool { lock.withLock { decided } }
    func requestPermission() async -> Bool { lock.withLock { decided } }
    func pending() async -> Set<String> { lock.withLock { pendingSet } }
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        lock.withLock { _ = pendingSet.insert(identifier) }
        return true
    }
    func removePending(_ identifiers: [String]) async { lock.withLock { pendingSet.subtract(identifiers) } }
    func removeDelivered(_ identifiers: [String]) async {}
}
