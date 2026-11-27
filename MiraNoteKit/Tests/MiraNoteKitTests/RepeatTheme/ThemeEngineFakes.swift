import Foundation
import XCTest
@testable import MiraNoteKit

/// Vision for the theme engine tests: each photo's print comes from
/// `vectors` (set by `ThemeHarness.addTheme`), its labels from `labels`.
final class ThemeFakeAnalyzer: PhotoAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var checkedIds: [String] = []
    private var storedRevision = 1
    var vectors: [String: [Float]] = [:]
    var labels: [String: [LabelScore]] = [:]
    /// Photos whose analysis says utility: never theme photos.
    var utility: Set<String> = []
    /// Photos whose checkup gives no theme vision (a simulator).
    var noVision: Set<String> = []
    /// Awaited inside each checkup, before it answers.
    var onCheckup: (@Sendable (String) async -> Void)?

    /// Every checkup, in order.
    var checked: [String] { lock.withLock { checkedIds } }
    var revision: Int {
        get { lock.withLock { storedRevision } }
        set { lock.withLock { storedRevision = newValue } }
    }

    func analyze(_ id: String) async -> PhotoAnalysis? {
        PhotoAnalysis(id: id, labels: [], broad: [], faces: 0, aesthetics: 0.5,
                      isUtility: utility.contains(id), featurePrint: nil)
    }

    func checkup(_ id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
        await onCheckup?(id)
        let revision = lock.withLock { () -> Int in
            checkedIds.append(id)
            return storedRevision
        }
        guard let analysis = await analyze(id) else { return nil }
        if noVision.contains(id) { return (analysis, nil) }
        let print = vectors[id] ?? ThemeHarness.vector(base: 3, noise: 0)
        return (analysis, ThemeVision(labels: labels[id] ?? [], print: print, printRevision: revision))
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

/// Qwen behind the backend: scripted replies, every call recorded.
final class FakeRoundClient: ThemeRoundClient, @unchecked Sendable {
    private let lock = NSLock()
    private var oneRequests: [RoundOneRequest] = []
    private var oneImages: [[(n: Int, jpeg: Data)]] = []
    private var shortenCalls: [[ShortenItem]] = []
    private var twoRequests: [RoundTwoRequest] = []
    private var twoImages: [[(n: Int, jpeg: Data)]] = []
    /// Thrown by the next round-2 calls, one each.
    var roundTwoErrors: [Error] = []
    /// The reply text of round-2 call `number` (1-based). The default says
    /// every photo belongs and nothing is alike.
    var roundTwoReply: @Sendable (RoundTwoRequest, Int) -> String = { request, _ in
        FakeRoundClient.roundTwoAnswer(request)
    }
    /// Thrown by the next round-1 calls, one each.
    var roundOneErrors: [Error] = []
    /// The reply text of round-1 call `number` (1-based). The default names
    /// the pile `Theme<number>` and picks no split.
    var roundOneReply: @Sendable (RoundOneRequest, Int) -> String = { _, number in
        #"{"sensitive": false, "pile_name": "Theme\#(number)", "chosen": "none", "groups": []}"#
    }
    var shortenReply: @Sendable ([ShortenItem]) -> String = { _ in #"{"items": []}"# }
    /// Runs inside each round-1 call (a slow answer).
    var onRoundOne: (@Sendable () -> Void)?
    static let usage = RoundUsage(promptTokens: 100, completionTokens: 20, costCny: 0.0006, model: "qwen-test")

    var roundOneRequests: [RoundOneRequest] { lock.withLock { oneRequests } }
    var roundOneImages: [[(n: Int, jpeg: Data)]] { lock.withLock { oneImages } }
    var shortenItems: [[ShortenItem]] { lock.withLock { shortenCalls } }
    var roundTwoRequests: [RoundTwoRequest] { lock.withLock { twoRequests } }
    var roundTwoImages: [[(n: Int, jpeg: Data)]] { lock.withLock { twoImages } }

    /// A round-2 reply for `request`'s photos: those in `notBelonging` do
    /// not belong, the rest do; `similar` names go in `similar_to`.
    static func roundTwoAnswer(_ request: RoundTwoRequest, notBelonging: Set<Int> = [],
                               similar: [String] = []) -> String {
        let photos = request.photos.map {
            #"{"id": \#($0.n), "belongs": \#(!notBelonging.contains($0.n)), "dup_of": null, "poor": false, "#
                + #""sensitive": false}"#
        }
        let alike = similar.map { #"{"name": "\#($0)", "level": "same"}"# }
        return #"{"photos": [\#(photos.joined(separator: ", "))], "similar_to": [\#(alike.joined(separator: ", "))]}"#
    }

    func roundOne(_ request: RoundOneRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        let number = try lock.withLock { () -> Int in
            oneRequests.append(request)
            oneImages.append(images)
            if !roundOneErrors.isEmpty { throw roundOneErrors.removeFirst() }
            return oneRequests.count
        }
        onRoundOne?()
        return RoundReply(reply: roundOneReply(request, number), where: ["A1": "evening"], usage: Self.usage)
    }

    func roundTwo(_ request: RoundTwoRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        let number = try lock.withLock { () -> Int in
            twoRequests.append(request)
            twoImages.append(images)
            if !roundTwoErrors.isEmpty { throw roundTwoErrors.removeFirst() }
            return twoRequests.count
        }
        return RoundReply(reply: roundTwoReply(request, number), where: [:], usage: Self.usage)
    }

    func shorten(_ items: [ShortenItem]) async throws -> RoundReply {
        lock.withLock { shortenCalls.append(items) }
        return RoundReply(reply: shortenReply(items), where: [:], usage: Self.usage)
    }
}

/// Lets a test hold every checkup until it opens.
final class CheckupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false

    var isWaiting: Bool { lock.withLock { !waiters.isEmpty } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock { () -> Bool in
                if open { return true }
                waiters.append(continuation)
                return false
            }
            if resume { continuation.resume() }
        }
    }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}

/// One phone for the engine tests: a library of synthetic theme photos (one
/// a day at noon UTC, `days` back from `start`), fake Vision and Qwen, and
/// every store in a temporary folder.
final class ThemeHarness {
    static let start = Date(timeIntervalSince1970: 1_795_262_400)  // 2026-11-21 12:00 UTC
    let directory: URL
    let clock = TestClock(ThemeHarness.start)
    let library = FakeLibrary(now: ThemeHarness.start, groups: [])
    let analyzer = ThemeFakeAnalyzer()
    let client = FakeRoundClient()
    var momentsCap = 5000
    var roundClient: ThemeRoundClient?
    var imageData: @Sendable (String) async -> Data? = { _ in ComposeMetaTests.tinyJPEG }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeEngineTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    var themes: ThemeLibrary { ThemeLibrary(file: directory.appendingPathComponent("library.json")) }
    var photos: ThemePhotoStore { ThemePhotoStore(directory: directory.appendingPathComponent("photos")) }
    var rounds: RoundLog { RoundLog(file: directory.appendingPathComponent("rounds.json")) }
    var window: ThemeWindowStore { ThemeWindowStore(file: directory.appendingPathComponent("window.json")) }
    var runs: ThemeRunLog { ThemeRunLog(file: directory.appendingPathComponent("runs.json")) }
    var cooldown: ThemeAskCooldownStore {
        ThemeAskCooldownStore(file: directory.appendingPathComponent("failed-asks.json"))
    }
    var analyses: AnalysisStore { AnalysisStore(directory: directory.appendingPathComponent("analysis")) }

    var deps: ThemeDependencies {
        let clock = clock
        return ThemeDependencies(
            library: library, analyzer: analyzer, analyses: analyses, photos: photos, themes: themes,
            rounds: rounds, window: window, runs: runs, client: roundClient ?? client, imageData: imageData,
            now: { clock.now }, calendar: calendar, momentsCap: momentsCap,
            cooldown: cooldown)
    }

    func engine() -> ThemeEngine { ThemeEngine(deps) }

    /// Noon UTC, `days` before `start`.
    func day(_ days: Int) -> Date { Self.start.addingTimeInterval(-Double(days) * 86_400) }

    /// A unit direction per theme (`base` 0...3) with a little noise per day,
    /// so photos of one theme sit about 0.01 apart and themes 1 apart.
    static func vector(base: Int, noise: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: 16)
        vector[base] = 1
        vector[4 + noise % 12] = 0.1
        return vector
    }

    /// One photo `"<prefix>-<day>"` a day at noon, `days` back.
    func addTheme(_ prefix: String, base: Int, days: [Int], labels: [LabelScore] = []) {
        for day in days {
            let id = "\(prefix)-\(day)"
            add(id, at: self.day(day))
            analyzer.vectors[id] = Self.vector(base: base, noise: day)
            if !labels.isEmpty { analyzer.labels[id] = labels }
        }
    }

    /// `extra` more shots a minute apart right after each day's photo, the
    /// same look: they join its moment (more photos, the same moments).
    func addBurst(_ prefix: String, days: [Int], extra: Int) {
        for day in days {
            for shot in 1...extra {
                let id = "\(prefix)-\(day)-b\(shot)"
                add(id, at: self.day(day).addingTimeInterval(Double(shot) * 60))
                analyzer.vectors[id] = analyzer.vectors["\(prefix)-\(day)"]
                analyzer.labels[id] = analyzer.labels["\(prefix)-\(day)"]
            }
        }
    }

    func add(_ id: String, at date: Date?) {
        library.assetsList.append(LibraryAsset(id: id, takenAt: date, location: nil, isFavorite: false,
                                               isEdited: false, isScreenshot: false, isHidden: false,
                                               isVideo: false, originalFilename: "IMG_0001.HEIC", burstId: nil))
    }

    /// The big row holding `photoId`.
    func bigRow(with photoId: String) -> ThemeRow? {
        themes.load().first { $0.kind == .big && $0.members.contains(photoId) }
    }

    /// A stored big row, as an earlier run would have left it.
    static func row(_ id: String, name: String, members: [String], lastAsked: Int, center: [Float],
                    status: ThemeStatus = .active) -> ThemeRow {
        ThemeRow(id: id, kind: .big, parentId: nil, name: name, noun: "", samePart: "", split: "none",
                 status: status, center: center, rule: nil, members: members, lastAskedCount: lastAsked,
                 flagged: false, followRatio: nil, where: nil)
    }
}
