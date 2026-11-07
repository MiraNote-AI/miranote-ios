import MiraNoteKit
import XCTest
@testable import MiraNote

/// Decision 8 past the first launch: the story's "..." menu replans only
/// where this install may schedule automatically, an App Store install
/// takes back the pushes a TestFlight build left pending, and a TestFlight
/// install's Settings switch opens the trigger, or takes it all back.
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
        AppSettings.storeDefaults.removeObject(forKey: TriggerController.optedInKey)
        super.tearDown()
    }

    private var ledger: PushLedgerStore { PushLedgerStore(file: folder.appendingPathComponent("ledger.json")) }
    private var log: ScheduleLogStore { ScheduleLogStore(file: folder.appendingPathComponent("log.json")) }
    private var preferences: PushPreferencesStore {
        PushPreferencesStore(file: folder.appendingPathComponent("preferences.json"))
    }

    /// A controller over the synthetic library and the fake AI, with the
    /// nights already planned once.
    private func makePlanned(optedIn: Bool = false) async -> TriggerController {
        let controller = makeController(optedIn: optedIn)
        await controller.scheduler.appBecameActive()
        return controller
    }

    /// A controller over the synthetic library and the fake AI.
    private func makeController(optedIn: Bool = false, prefetchFonts: @escaping @Sendable () -> Void = {})
        -> TriggerController {
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
            permissions: .none, fakeAI: true, optedIn: optedIn, prefetchFonts: prefetchFonts)
        return controller
    }

    private var active: [LedgerEntry] {
        ledger.load().filter(\.isActive).sorted { $0.scheduledFor < $1.scheduledFor }
    }

    /// A development build: open, no switch.
    private static let open = InstallSource.Gates(showsDebugEntry: true, schedulesAutomatically: true)
    /// A TestFlight install: closed until the Settings switch is on.
    private static let testFlight = InstallSource.Gates(showsDebugEntry: false, schedulesAutomatically: false,
                                                        offersOptIn: true)
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

    func testMenuOnAnOpenInstallReplans() async throws {
        let controller = await makePlanned()
        _ = await controller.resolveGates { Self.open }
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

    func testOpenInstallKeepsPendingPushes() async throws {
        let controller = await makePlanned()
        let before = active
        _ = await controller.resolveGates { Self.open }
        XCTAssertEqual(active, before)
    }

    // MARK: The TestFlight switch

    func testTestFlightWithTheSwitchOnKeepsPendingPushesAndReplans() async throws {
        let controller = await makePlanned(optedIn: true)
        let before = active
        _ = await controller.resolveGates { Self.testFlight }
        XCTAssertEqual(active, before)
        let target = try XCTUnwrap(active.first)
        let runs = log.runs().count
        await controller.menu(.notThisDay, pushId: target.pushId).value
        XCTAssertEqual(log.runs().count, runs + 1, "the switch is on: the menu replans")
    }

    /// Pushes left from when the switch was on (the app killed before the
    /// take-back finished, say) go at the next launch.
    func testTestFlightWithTheSwitchOffTakesBackPendingPushesAtLaunch() async throws {
        let controller = await makePlanned()
        XCTAssertFalse(active.isEmpty)
        notifier.add("other.app")
        _ = await controller.resolveGates { Self.testFlight }
        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(ledger.load().allSatisfy { $0.removedReason == .optedOut })
        XCTAssertEqual(notifier.pendingIds, ["other.app"], "only our pushes go")
    }

    func testTurningTheSwitchOffTakesBackPendingPushes() async throws {
        let controller = await makePlanned(optedIn: true)
        _ = await controller.resolveGates { Self.testFlight }
        XCTAssertFalse(active.isEmpty)
        controller.optedIn = false
        await controller.optInChange?.value
        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(ledger.load().allSatisfy { $0.removedReason == .optedOut })
        XCTAssertFalse(AppSettings.storeDefaults.bool(forKey: TriggerController.optedInKey), "kept off")
        let off = await controller.scheduler.isOff
        XCTAssertTrue(off, "no run starts, whoever asks")
    }

    /// Off at launch, then on: the scheduler may run again.
    func testTurningTheSwitchOnLetsTheSchedulerRun() async {
        let controller = makeController()
        _ = await controller.resolveGates { Self.testFlight }
        let offAtLaunch = await controller.scheduler.isOff
        XCTAssertTrue(offAtLaunch)
        controller.optedIn = true
        await controller.optInChange?.value
        let off = await controller.scheduler.isOff
        XCTAssertFalse(off)
    }

    /// Turned on and off again quickly: the scheduler ends as the switch does.
    func testQuickTurnsReachTheSchedulerInOrder() async {
        let controller = makeController()
        _ = await controller.resolveGates { Self.testFlight }
        controller.optedIn = true
        controller.optedIn = false
        controller.optedIn = true
        controller.optedIn = false
        controller.optedIn = true
        await controller.optInChange?.value
        // Ends on "on": a turn off landing after the last turn on would leave it off.
        let off = await controller.scheduler.isOff
        XCTAssertFalse(off)
    }

    func testTheSwitchIsKept() async {
        let controller = makeController()
        controller.optedIn = true
        XCTAssertTrue(AppSettings.storeDefaults.bool(forKey: TriggerController.optedInKey))
    }

    // MARK: The ending's fonts (review of iOS#172, point 3)

    /// Kaiti and Weibei download only where the trigger can show: never for
    /// an App Store install or a closed one.
    func testFontsWaitForAnOpenGate() async {
        for gates in [InstallSource.Gates.closed, Self.appStore, Self.testFlight] {
            let fetched = FontFetches()
            _ = await makeController(prefetchFonts: { fetched.count() }).resolveGates { gates }
            XCTAssertEqual(fetched.value, 0, "\(gates)")
        }
    }

    func testFontsStartOnceTheGatesOpen() async {
        let fetched = FontFetches()
        let controller = makeController(prefetchFonts: { fetched.count() })
        _ = await controller.resolveGates { Self.open }
        _ = await controller.resolveGates { Self.open }
        XCTAssertEqual(fetched.value, 1, "once")
    }

    func testFontsStartWhenTheSwitchTurnsOn() async {
        let fetched = FontFetches()
        let controller = makeController(prefetchFonts: { fetched.count() })
        _ = await controller.resolveGates { Self.testFlight }
        XCTAssertEqual(fetched.value, 0)
        controller.optedIn = true
        await controller.optInChange?.value
        XCTAssertEqual(fetched.value, 1)
    }

    func testGatesResolveOncePerLaunch() async {
        let controller = await makePlanned()
        let first = await controller.resolveGates { Self.open }
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
