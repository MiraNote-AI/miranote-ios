import MiraNoteKit
import XCTest
@testable import MiraNote

/// Decision 8 past the first launch: the story's "..." menu replans only
/// where this install may schedule automatically, and an App Store install
/// takes back the pushes a TestFlight build left pending.
@MainActor
final class TriggerInstallGateTests: XCTestCase {
    private var folder: URL!
    private var notifier: RecordingNotifier!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        notifier = RecordingNotifier()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private var ledger: PushLedgerStore { PushLedgerStore(file: folder.appendingPathComponent("ledger.json")) }
    private var log: ScheduleLogStore { ScheduleLogStore(file: folder.appendingPathComponent("log.json")) }
    private var preferences: PushPreferencesStore {
        PushPreferencesStore(file: folder.appendingPathComponent("preferences.json"))
    }

    /// A controller over the synthetic library and the fake AI, with the
    /// nights already planned once.
    private func makePlanned() async -> TriggerController {
        let controller = makeController()
        await controller.scheduler.appBecameActive()
        return controller
    }

    /// A controller over the synthetic library and the fake AI.
    private func makeController() -> TriggerController {
        let library = SyntheticTriggerLibrary()
        let records = PushRecordStore(directory: folder.appendingPathComponent("pushes"))
        let folder = self.folder!
        let notifier = self.notifier!
        let controller = TriggerController(
            photos: library, records: records,
            dependencies: { flag in
                SchedulerDependencies(
                    library: library, analyzer: library, places: UITestPlaces(), client: UITestComposeClient(),
                    notifications: notifier,
                    analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")),
                    records: records,
                    ledger: PushLedgerStore(file: folder.appendingPathComponent("ledger.json")),
                    preferences: PushPreferencesStore(file: folder.appendingPathComponent("preferences.json")),
                    cache: AIResultCache(file: folder.appendingPathComponent("cache.json")),
                    log: ScheduleLogStore(file: folder.appendingPathComponent("log.json")),
                    state: SchedulerStateStore(file: folder.appendingPathComponent("state.json")),
                    lastRun: LastRunStore(file: folder.appendingPathComponent("last-run.json")),
                    fakeAI: { flag.value }, zh: TriggerContent.zh)
            },
            permissions: .none, fakeAI: true)
        return controller
    }

    private var active: [LedgerEntry] {
        ledger.load().filter(\.isActive).sorted { $0.scheduledFor < $1.scheduledFor }
    }

    private static let testFlight = InstallSource.Gates(showsDebugEntry: true, schedulesAutomatically: true)
    private static let appStore = InstallSource.Gates(showsDebugEntry: false, schedulesAutomatically: false,
                                                       isAppStore: true)

    func testMenuOnAClosedInstallSavesButDoesNotReplan() async throws {
        let controller = await makePlanned()
        _ = await controller.resolveGates { .closed }
        let target = try XCTUnwrap(active.first)
        let runs = log.runs().count
        await controller.menu(.notThisDay, pushId: target.pushId).value
        let entry = try XCTUnwrap(ledger.load().first { $0.pushId == target.pushId })
        XCTAssertEqual(entry.menuAction, .notThisDay, "the ledger is stamped")
        XCTAssertEqual(entry.removedReason, .menuDay, "its push is taken back")
        XCTAssertNotNil(preferences.load().blockedDays[target.belongsTo], "the choice is kept")
        XCTAssertEqual(log.runs().count, runs, "no run: nothing reaches the backend")
    }

    func testMenuBeforeTheGatesResolveDoesNotReplan() async throws {
        let controller = await makePlanned()
        let target = try XCTUnwrap(active.first)
        let runs = log.runs().count
        await controller.menu(.notThisDay, pushId: target.pushId).value
        XCTAssertEqual(ledger.load().first { $0.pushId == target.pushId }?.removedReason, .menuDay)
        XCTAssertEqual(log.runs().count, runs, "unknown install: fail closed")
    }

    func testMenuOnATestFlightInstallReplans() async throws {
        let controller = await makePlanned()
        _ = await controller.resolveGates { Self.testFlight }
        let target = try XCTUnwrap(active.first)
        let runs = log.runs().count
        await controller.menu(.notThisDay, pushId: target.pushId).value
        XCTAssertEqual(log.runs().count, runs + 1)
        XCTAssertEqual(log.runs().first?.trigger, "menu", "newest first")
    }

    func testAppStoreInstallTakesBackPendingPushes() async throws {
        let controller = await makePlanned()
        XCTAssertFalse(active.isEmpty, "the TestFlight build left pushes")
        notifier.add("other.app")
        let gates = await controller.resolveGates { Self.appStore }
        XCTAssertTrue(gates.isAppStore)
        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(ledger.load().allSatisfy { $0.removedReason == .appStore })
        XCTAssertEqual(notifier.pendingIds, ["other.app"], "only our pushes go")
    }

    func testTestFlightInstallKeepsPendingPushes() async throws {
        let controller = await makePlanned()
        let before = active
        _ = await controller.resolveGates { Self.testFlight }
        XCTAssertEqual(active, before)
    }

    /// The ending's fonts (Kaiti, Weibei) start downloading at launch,
    /// not after StoreKit has answered -- which can take seconds, or say
    /// nothing at all.
    func testFontsStartWithoutWaitingForTheInstallSource() async {
        let controller = makeController()
        let fetched = FontFetches()
        let (answer, answered) = AsyncStream<Void>.makeStream()
        let gates = Task {
            await controller.resolveGates({
                for await _ in answer {}
                return .closed
            }, prefetchFonts: { fetched.count() })
        }
        for _ in 0..<50 where fetched.value == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fetched.value, 1, "started before the answer")
        answered.finish()
        _ = await gates.value
        XCTAssertEqual(fetched.value, 1, "once")
    }

    func testGatesResolveOncePerLaunch() async {
        let controller = await makePlanned()
        let first = await controller.resolveGates { Self.testFlight }
        let second = await controller.resolveGates { Self.appStore }
        XCTAssertEqual(first, second, "HomeFlow made again gets the first answer")
    }
}

/// How often the fonts were asked for.
private final class FontFetches: @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    var value: Int { lock.withLock { fetches } }
    func count() { lock.withLock { fetches += 1 } }
}

/// A notification centre that keeps pending ids in memory.
private final class RecordingNotifier: PushNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSet: Set<String> = []
    var pendingIds: Set<String> { lock.withLock { pendingSet } }

    func add(_ identifier: String) { lock.withLock { _ = pendingSet.insert(identifier) } }
    func isAllowed() async -> Bool { true }
    func requestPermission() async -> Bool { true }
    func pending() async -> Set<String> { pendingIds }
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        add(identifier)
        return true
    }
    func removePending(_ identifiers: [String]) async { lock.withLock { pendingSet.subtract(identifiers) } }
    func removeDelivered(_ identifiers: [String]) async {}
}
