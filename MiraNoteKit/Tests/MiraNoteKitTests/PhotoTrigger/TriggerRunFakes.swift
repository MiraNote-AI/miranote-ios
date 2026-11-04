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

    func analyze(_ id: String) async -> PhotoAnalysis? {
        lock.withLock { analyzedIds.append(id) }
        return PhotoAnalysis(id: id, labels: ["food"], broad: [.food_drink], faces: 0, aesthetics: nil,
                             isUtility: false, featurePrint: nil)
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }
}

struct NoPlaces: PlaceNaming {
    func name(for point: GeoPoint) async -> String? { nil }
}

final class FakeNotifier: PushNotificationCenter, @unchecked Sendable {
    var allowed = true
    private let lock = NSLock()
    private var recordsList: [PushRecord] = []
    private var identifiersList: [String] = []
    private var pendingSet: Set<String> = []
    private var removedPendingList: [String] = []
    private var removedDeliveredList: [String] = []
    var scheduled: [PushRecord] { lock.withLock { recordsList } }
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
    func pending() async -> Set<String> { pendingIds }
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        lock.withLock {
            recordsList.append(record)
            identifiersList.append(identifier)
            pendingSet.insert(identifier)
        }
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

    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        try lock.withLock {
            if !submitErrors.isEmpty { throw submitErrors.removeFirst() }
            submitted.append(meta.date)
            lastMeta = meta
            lastPhotoNumbers = photos.map(\.id)
            let job = "job-\(submitted.count)"
            jobs[job] = meta
            return job
        }
    }

    func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus] {
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
