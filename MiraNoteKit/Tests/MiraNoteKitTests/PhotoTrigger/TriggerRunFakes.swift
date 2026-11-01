import XCTest
@testable import MiraNoteKit

/// Five fragments, 3-7 days old, ranked by size: group 0 (10 photos) is
/// rank 1 ... group 4 (4 photos) rank 5. No GPS, so no place lookups.
final class FakeLibrary: PhotoLibraryReading, @unchecked Sendable {
    let now: Date
    var access: PhotoAccess = .full
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
    func assets(since date: Date) async -> [LibraryAsset] { assetsList.filter { ($0.takenAt ?? .distantPast) >= date } }
    func uploadData(for id: String) async -> Data? { ComposeMetaTests.tinyJPEG }
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

    func distance(_ first: Data, _ second: Data) -> Float? { nil }
}

struct NoPlaces: PlaceNaming {
    func name(for point: GeoPoint) async -> String? { nil }
}

final class FakeNotifier: TriggerNotifying, @unchecked Sendable {
    var allowed = true
    private let lock = NSLock()
    private var recordsList: [PushRecord] = []
    var scheduled: [PushRecord] { lock.withLock { recordsList } }

    func requestPermission() async -> Bool { allowed }
    func schedule(_ record: PushRecord) async -> Bool {
        lock.withLock { recordsList.append(record) }
        return true
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
    private var polls: [String: Int] = [:]
    private var jobs: [String: ComposeMeta] = [:]

    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        try lock.withLock {
            if !submitErrors.isEmpty { throw submitErrors.removeFirst() }
            submitted.append(meta.date)
            let job = "job-\(submitted.count)"
            jobs[job] = meta
            return job
        }
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
