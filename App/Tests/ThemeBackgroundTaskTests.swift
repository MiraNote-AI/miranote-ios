import BackgroundTasks
import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// The repeat-theme finder in the app: the background task (registered and
/// asked for only where the trigger may run, stopped when iOS takes the
/// time back) and the Vision checkup that feeds it.
final class ThemeBackgroundTaskTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    // MARK: - The background task

    func testBackgroundTaskRunsOnlyWhenGateOpen() async {
        // Registered at every launch, whatever the gates: a request left by
        // an earlier launch must find a handler. Registering asks for no run.
        let open = FakeTaskScheduler()
        ThemeBackgroundTask(scheduler: open).register { _ in }
        XCTAssertEqual(open.registered, ["app.miranote.photo-trigger.themes"])
        XCTAssertTrue(open.submitted.isEmpty)

        // Woken with the gates closed (the switch went off since): nothing
        // runs, nothing is asked for again, a pending request is taken
        // back, the task is done.
        let runner = FakeThemeRunner()
        let task = FakeProcessingTask()
        let report = await ThemeBackgroundTask(scheduler: open).run(task, engine: runner, gatesOpen: { false })
        XCTAssertNil(report)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertTrue(open.submitted.isEmpty)
        XCTAssertEqual(open.cancelled, ["app.miranote.photo-trigger.themes"])
        XCTAssertEqual(task.completions, [true])

        // Gates open: one background run, until start + 4 minutes, then the
        // next one is asked for (charging and online).
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let woken = FakeProcessingTask()
        let background = ThemeBackgroundTask(scheduler: open, now: { start })
        _ = await background.run(woken, engine: runner, gatesOpen: { true })
        XCTAssertEqual(runner.runs.count, 1)
        XCTAssertEqual(runner.runs.first?.trigger, .background)
        XCTAssertEqual(runner.runs.first?.deadline, start.addingTimeInterval(4 * 60))
        XCTAssertEqual(woken.completions, [true])
        let request = open.submitted.first as? BGProcessingTaskRequest
        XCTAssertEqual(open.submitted.count, 1)
        XCTAssertEqual(request?.identifier, "app.miranote.photo-trigger.themes")
        XCTAssertEqual(request?.requiresExternalPower, true)
        XCTAssertEqual(request?.requiresNetworkConnectivity, true)
        XCTAssertEqual(open.cancelled.count, 1, "an open run takes nothing back")
    }

    func testNoRunStartsAfterTheTaskExpired() async {
        let scheduler = FakeTaskScheduler()
        let runner = FakeThemeRunner()
        let task = FakeProcessingTask()
        // iOS takes the time back while the gates are still resolving.
        let report = await ThemeBackgroundTask(scheduler: scheduler).run(task, engine: runner, gatesOpen: {
            task.expire()
            return true
        })
        XCTAssertNil(report)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(task.completions, [false])
        // Nothing ran, and the gates might have come back closed (an App
        // Store build that inherited a request): nothing is asked for again.
        XCTAssertTrue(scheduler.submitted.isEmpty)
    }

    func testBackgroundRunStopsAtExpiration() async throws {
        let library = DatedLibrary(days: 30)
        let task = FakeProcessingTask()
        // iOS takes the time back while the third photo is read.
        let analyzer = SlowAnalyzer(onCheckup: { count in if count == 3 { task.expire() } })
        let runs = ThemeRunLog(file: folder.appendingPathComponent("runs.json"))
        let engine = ThemeEngine(ThemeDependencies(
            library: library, analyzer: analyzer,
            analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")),
            photos: ThemePhotoStore(directory: folder.appendingPathComponent("photos")),
            themes: ThemeLibrary(file: folder.appendingPathComponent("library.json")),
            rounds: RoundLog(file: folder.appendingPathComponent("rounds.json")),
            window: ThemeWindowStore(file: folder.appendingPathComponent("window.json")),
            runs: runs, client: UnreachableRounds(), imageData: { _ in nil }
        ))
        let scheduler = FakeTaskScheduler()

        let ran = await ThemeBackgroundTask(scheduler: scheduler).run(task, engine: engine, gatesOpen: { true })
        let report = try XCTUnwrap(ran)

        XCTAssertEqual(task.completions, [false], "completed once, at the expiration")
        XCTAssertEqual(report.trigger, .background)
        XCTAssertEqual(report.checkedNew, 3, "the run stopped at the next photo")
        XCTAssertEqual(report.photos, 30)
        XCTAssertEqual(report.asked, 0)
        XCTAssertFalse(report.failures.isEmpty)
        XCTAssertGreaterThanOrEqual(report.checkupMs, 3 * SlowAnalyzer.milliseconds, "the time it ran is recorded")
        let kept = runs.load().last
        XCTAssertEqual(kept?.trigger, .background, "the debug page sees the run")
        XCTAssertEqual(kept?.checkupMs, report.checkupMs)
        XCTAssertEqual(scheduler.submitted.count, 1, "the next run is asked for")
    }

    // MARK: - The Vision checkup

    func testCheckupGivesThemeVisionOnDevicePathOnly() async throws {
        let analyzer = PhotoAnalyzer(photos: DrawnPhotos())
        let checkup = await analyzer.checkup("drawn")
        let checked = try XCTUnwrap(checkup)
        let analysis = await analyzer.analyze("drawn")
        XCTAssertEqual(checked.analysis, analysis, "V1's analysis is what analyze gives")
        #if targetEnvironment(simulator)
        // As V1 keeps no prints there: the simulator's are all alike.
        XCTAssertNil(checked.theme)
        XCTAssertNil(analysis?.featurePrint)
        #else
        let theme = try XCTUnwrap(checked.theme)
        XCTAssertFalse(theme.print.isEmpty)
        XCTAssertLessThanOrEqual(theme.labels.count, 20)
        XCTAssertTrue(theme.labels.allSatisfy { $0.confidence >= 0.1 })
        #endif

        // The device path's pieces. Labels: the top 20 at >= 0.1, all of
        // them (not V1's high-precision few), best first.
        let classified = (0..<30).map { (id: "label\($0)", confidence: Float($0) / 100 + 0.05) }
        let labels = PhotoAnalyzer.themeLabels(classified)
        XCTAssertEqual(labels.count, 20)
        XCTAssertEqual(labels.first, LabelScore(id: "label29", confidence: 0.34))
        XCTAssertEqual(labels.last?.id, "label10")
        XCTAssertTrue(PhotoAnalyzer.themeLabels([(id: "faint", confidence: 0.09)]).isEmpty)

        // Prints: the observation's bytes as floats, from either element type.
        let floats: [Float] = [0.5, -1, 2]
        XCTAssertEqual(PhotoAnalyzer.printFloats(bytes(of: floats), elementType: .float, count: 3), floats)
        let doubles: [Double] = [0.5, -1, 2]
        XCTAssertEqual(PhotoAnalyzer.printFloats(bytes(of: doubles), elementType: .double, count: 3), floats)
        XCTAssertNil(PhotoAnalyzer.printFloats(bytes(of: floats), elementType: .float, count: 4), "short data")
        XCTAssertNil(PhotoAnalyzer.printFloats(bytes(of: floats), elementType: .unknown, count: 3))
    }

    private func bytes<T>(of values: [T]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

// MARK: - Fakes

private final class FakeTaskScheduler: ThemeTaskScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String] = []
    private var requests: [BGTaskRequest] = []
    private var cancels: [String] = []

    var registered: [String] { lock.withLock { identifiers } }
    var submitted: [BGTaskRequest] { lock.withLock { requests } }
    var cancelled: [String] { lock.withLock { cancels } }

    func register(_ identifier: String, launchHandler: @escaping (ThemeProcessingTask) -> Void) -> Bool {
        lock.withLock { identifiers.append(identifier) }
        return true
    }

    func submit(_ request: BGTaskRequest) throws {
        lock.withLock { requests.append(request) }
    }

    func cancel(_ identifier: String) {
        lock.withLock { cancels.append(identifier) }
    }
}

private final class FakeProcessingTask: ThemeProcessingTask, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?
    private var done: [Bool] = []

    var expirationHandler: (() -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    var completions: [Bool] { lock.withLock { done } }

    func setTaskCompleted(success: Bool) {
        lock.withLock { done.append(success) }
    }

    /// What iOS does when the time is up.
    func expire() {
        expirationHandler?()
    }
}

private final class FakeThemeRunner: ThemeRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(trigger: ThemeTrigger, deadline: Date?)] = []

    var runs: [(trigger: ThemeTrigger, deadline: Date?)] { lock.withLock { calls } }

    func run(trigger: ThemeTrigger, deadline: Date?) async -> ThemeRunReport {
        lock.withLock { calls.append((trigger, deadline)) }
        return ThemeRunReport(at: Date(), trigger: trigger, photos: 0, checkedNew: 0, moments: 0, piles: [],
                              checkupMs: 0, clusterMs: 0, peakMemoryMB: nil, asked: 0, failures: [])
    }

    func stopEarly() {}
}

/// One camera photo a day, `days` days back from now.
private struct DatedLibrary: PhotoLibraryReading {
    let days: Int

    func requestAccess() async -> PhotoAccess { .full }

    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset] {
        (0..<days).map { day in
            LibraryAsset(id: "p-\(day)", takenAt: Date().addingTimeInterval(-Double(day) * 86_400 - 60),
                         location: nil, isFavorite: false, isEdited: false, isScreenshot: false, isHidden: false,
                         isVideo: false, originalFilename: "IMG_\(day).HEIC", burstId: nil)
        }
    }

    func uploadData(for id: String) async -> Data? { nil }
}

/// Vision that takes `milliseconds` a photo and always has a theme vision.
private final class SlowAnalyzer: PhotoAnalyzing, @unchecked Sendable {
    static let milliseconds = 20
    private let lock = NSLock()
    private var count = 0
    private let onCheckup: (Int) -> Void

    init(onCheckup: @escaping (Int) -> Void) {
        self.onCheckup = onCheckup
    }

    func analyze(_ id: String) async -> PhotoAnalysis? {
        PhotoAnalysis(id: id, labels: [], broad: [], faces: 0, aesthetics: 0.5, isUtility: false, featurePrint: nil)
    }

    func checkup(_ id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
        try? await Task.sleep(nanoseconds: UInt64(Self.milliseconds) * 1_000_000)
        let number = lock.withLock { () -> Int in
            count += 1
            return count
        }
        onCheckup(number)
        guard let analysis = await analyze(id) else { return nil }
        return (analysis, ThemeVision(labels: [], print: [1, 0, 0], printRevision: 1))
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

private struct UnreachableRounds: ThemeRoundClient {
    func roundOne(_ request: RoundOneRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        throw ThemeRoundError.unreachable
    }

    func roundTwo(_ request: RoundTwoRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        throw ThemeRoundError.unreachable
    }

    func shorten(_ items: [ShortenItem]) async throws -> RoundReply {
        throw ThemeRoundError.unreachable
    }
}

/// One drawn picture (no library): a sky, a field and a sun.
private struct DrawnPhotos: TriggerPhotoProviding {
    func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 384), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 220))
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 220, width: 512, height: 164))
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 360, y: 40, width: 90, height: 90))
        }
    }

    func existing(_ ids: [String]) async -> Set<String> { Set(ids) }
}
