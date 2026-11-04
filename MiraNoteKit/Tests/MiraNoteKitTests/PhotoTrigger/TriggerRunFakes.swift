import XCTest
@testable import MiraNoteKit

/// Five fragments, 3-7 days old, ranked by size: group 0 (10 photos) is
/// rank 1 ... group 4 (4 photos) rank 5. No GPS, so no place lookups.
final class FakeLibrary: PhotoLibraryReading, @unchecked Sendable {
    let now: Date
    var access: PhotoAccess = .full
    /// Photos whose bytes cannot be read.
    var unreadable: Set<String> = []
    var assetsList: [LibraryAsset]

    init(now: Date, groups: [Int] = [10, 8, 6, 5, 4]) {
        self.now = now
        var list: [LibraryAsset] = []
        for (group, count) in groups.enumerated() {
            let start = now.addingTimeInterval(-Double(group + 3) * 86_400).addingTimeInterval(-6 * 3600)
            for index in 0..<count {
                let takenAt = start.addingTimeInterval(Double(index) * 1500)
                list.append(LibraryAsset(id: "g\(group)-\(index)", takenAt: takenAt,
                                         location: nil, isFavorite: false, isEdited: false, isScreenshot: false,
                                         isHidden: false, isVideo: false, originalFilename: "IMG_\(index).HEIC",
                                         burstId: nil))
            }
        }
        assetsList = list
    }

    /// Adds a group of `count` photos 25 min apart from `start`, ids "<prefix>-<n>".
    func add(_ prefix: String, start: Date, count: Int, location: GeoPoint? = nil) {
        for index in 0..<count {
            let takenAt = start.addingTimeInterval(Double(index) * 1500)
            assetsList.append(LibraryAsset(id: "\(prefix)-\(index)", takenAt: takenAt, location: location,
                                           isFavorite: false, isEdited: false, isScreenshot: false, isHidden: false,
                                           isVideo: false, originalFilename: "IMG_\(index).HEIC", burstId: nil))
        }
    }

    /// Drops every photo of the group "<prefix>-n".
    func remove(_ prefix: String) {
        assetsList.removeAll { $0.id.hasPrefix(prefix + "-") }
    }

    func requestAccess() async -> PhotoAccess { access }
    private let lock = NSLock()
    private var knownLog: [[String: String]] = []
    /// The known file names each press passed in.
    var knownFilenames: [[String: String]] { lock.withLock { knownLog } }

    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset] {
        lock.withLock { knownLog.append(knownFilenames) }
        return assetsList.filter { ($0.takenAt ?? .distantPast) >= date }
    }
    func uploadData(for id: String) async -> Data? { unreadable.contains(id) ? nil : ComposeMetaTests.tinyJPEG }
}

final class FakeAnalyzer: PhotoAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var analyzedIds: [String] = []
    var analyzed: [String] { lock.withLock { analyzedIds } }
    /// Group prefix ("g3") -> its label; everything else is food.
    var labels: [String: String] = [:]

    func analyze(_ id: String) async -> PhotoAnalysis? {
        let label = lock.withLock { () -> String in
            analyzedIds.append(id)
            return labels[String(id.split(separator: "-").first ?? "")] ?? "food"
        }
        return PhotoAnalysis(id: id, labels: [label], broad: BroadCategory.from(labels: [label]), faces: 0,
                             aesthetics: nil, isUtility: false, featurePrint: nil)
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

struct NoPlaces: PlaceNaming {
    func name(for point: GeoPoint) async -> String? { nil }
}

struct FixedPlace: PlaceNaming {
    func name(for point: GeoPoint) async -> String? { "Riverside Park" }
}

final class FakeNotifier: PushNotificationCenter, @unchecked Sendable {
    var allowed = true
    /// `schedule` adds nothing and answers false.
    var refuseSchedule = false
    /// Runs inside `schedule`, before it answers (races with the caller).
    var onSchedule: (@Sendable () async -> Void)?
    private var onPendingOnceHook: (@Sendable () async -> Void)?
    /// Runs inside the next `pending` call only, before it answers.
    var onPendingOnce: (@Sendable () async -> Void)? {
        get { lock.withLock { onPendingOnceHook } }
        set { lock.withLock { onPendingOnceHook = newValue } }
    }
    private let lock = NSLock()
    private var recordsList: [PushRecord] = []
    private var identifiersList: [String] = []
    private var pendingSet: Set<String> = []
    private var removedPendingList: [String] = []
    private var removedDeliveredList: [String] = []
    private var atList: [DateComponents?] = []
    var scheduled: [PushRecord] { lock.withLock { recordsList } }
    /// The `at` of each `schedule` call, in order (nil: 10 s out).
    var scheduledAt: [DateComponents?] { lock.withLock { atList } }
    /// The identifier of each `schedule` call, in order.
    var scheduledIdentifiers: [String] { lock.withLock { identifiersList } }
    var removedPending: [String] { lock.withLock { removedPendingList } }
    var removedDelivered: [String] { lock.withLock { removedDeliveredList } }
    /// Pending ids; tests may put foreign ones (e.g. "other.x") in.
    var pendingIds: Set<String> {
        get { lock.withLock { pendingSet } }
        set { lock.withLock { pendingSet = newValue } }
    }

    func isAllowed() async -> Bool { allowed }
    func requestPermission() async -> Bool { allowed }
    func pending() async -> Set<String> {
        let hook = lock.withLock { () -> (@Sendable () async -> Void)? in
            defer { onPendingOnceHook = nil }
            return onPendingOnceHook
        }
        await hook?()
        return pendingIds
    }
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        if refuseSchedule { return false }
        lock.withLock {
            recordsList.append(record)
            identifiersList.append(identifier)
            atList.append(at)
            pendingSet.insert(identifier)
        }
        await onSchedule?()
        return true
    }
    func removePending(_ identifiers: [String]) async {
        lock.withLock {
            removedPendingList += identifiers
            pendingSet.subtract(identifiers)
        }
    }
    func removeDelivered(_ identifiers: [String]) async {
        lock.withLock { removedDeliveredList += identifiers }
    }
}

/// Answers per group (by the first photo's date): a list of poll answers,
/// the last repeated. Groups with no script come back ok.
final class FakeClient: ComposeClient, @unchecked Sendable {
    enum Answer { case running, ok, rejected, expired, rateLimited, timeoutError }
    private let lock = NSLock()
    var scripts: [String: [Answer]] = [:]
    var submitErrors: [ComposeError] = []
    private(set) var submitted: [String] = []
    private(set) var lastMeta: ComposeMeta?
    private(set) var lastPhotoNumbers: [String] = []
    private var polls: [String: Int] = [:]
    private var jobs: [String: ComposeMeta] = [:]
    private var eventList: [String] = []
    /// "submit <date>" and "pollMany <n ids>", in order.
    var events: [String] { lock.withLock { eventList } }
    var pollManyCount: Int { events.filter { $0.hasPrefix("pollMany") }.count }

    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        try lock.withLock {
            if !submitErrors.isEmpty { throw submitErrors.removeFirst() }
            submitted.append(meta.date)
            eventList.append("submit \(meta.date)")
            lastMeta = meta
            lastPhotoNumbers = photos.map(\.id)
            let job = "job-\(submitted.count)"
            jobs[job] = meta
            return job
        }
    }

    func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus] {
        lock.withLock { eventList.append("pollMany \(jobIds.count)") }
        var result: [String: ComposeJobStatus] = [:]
        for id in jobIds { result[id] = try await poll(id) }
        return result
    }

    func poll(_ jobId: String) async throws -> ComposeJobStatus {
        try lock.withLock {
            guard let meta = jobs[jobId] else { return .expired }
            let script = scripts[meta.date] ?? [.ok]
            let count = polls[jobId, default: 0]
            polls[jobId] = count + 1
            switch script[min(count, script.count - 1)] {
            case .running: return .running
            case .rejected: return .rejected(reason: "too_few_selected", message: "no \(meta.date)")
            case .expired: return .expired
            case .rateLimited: throw ComposeError.rateLimited
            case .timeoutError: return .failed(reason: "timeout", message: "slow")
            case .ok:
                let memory = TriggerMemoryTests.memory(ids: ["P1", "P2", "P3"], peak: "P2")
                return .ok(TriggerMemory(id: meta.groupKey, date: meta.date, daypart: memory.daypart,
                                         push: memory.push, story: memory.story, ending: memory.ending))
            }
        }
    }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [TimeInterval] = []
    var durations: [TimeInterval] { lock.withLock { all } }
    func record(_ duration: TimeInterval) { lock.withLock { all.append(duration) } }
}

/// A clock the injected sleep moves on: tests never wait for real.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

/// Runs `action` from inside the injected sleep (n = 1 for the first sleep).
final class SleepHook: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var action: (@Sendable (Int) async -> Void)?
    func fire() async {
        let (number, action) = lock.withLock { () -> (Int, (@Sendable (Int) async -> Void)?) in
            count += 1
            return (count, self.action)
        }
        await action?(number)
    }
}

/// The phone's time zone, changeable mid-test.
final class ZoneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeZone
    init(_ zone: TimeZone) { value = zone }
    var zone: TimeZone {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
