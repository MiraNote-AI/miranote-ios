import Foundation

/// One group's round trip to the backend (handoff 5): read and prepare the
/// photos (a photo that cannot be read within 20 s is left out and the
/// rest renumbered; under three left, the group does not pass), submit,
/// then poll every 5 s for up to 6 minutes of waiting (the backend's own
/// cap is 5 minutes, per the 2026-11-01 contract change). A 429 waits 10 s;
/// an expired job is submitted once more; a submit or poll cut short (no
/// connection, the app went to the background) is tried up to three times.
/// The budget counts the waits, so time spent suspended in the background
/// does not use it up.
struct ComposeSession {
    static let pollInterval: TimeInterval = 5
    static let rateLimitWait: TimeInterval = 10
    static let budget: TimeInterval = 360
    /// Consecutive transport failures tolerated while submitting or polling.
    static let transportRetries = 3
    /// How long one photo may take to read before it is left out.
    static let readTimeout: TimeInterval = 20
    /// The message of a group with too few readable photos (a catalog key).
    static let unreadableMessage = "Too few of its photos could be read"

    let library: PhotoLibraryReading
    let client: ComposeClient
    let sleep: @Sendable (TimeInterval) async throws -> Void

    init(library: PhotoLibraryReading, client: ComposeClient,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.library = library
        self.client = client
        self.sleep = sleep
    }

    init(deps: TriggerDependencies) {
        self.init(library: deps.library, client: deps.client, sleep: deps.sleep)
    }

    /// What came back, and the numbering actually sent.
    struct Composed {
        let memory: TriggerMemory
        let photoIds: [String: String]
    }

    /// A group ready to submit: the meta of the photos that could be read,
    /// their numbering, and their upload files.
    struct Prepared: Sendable {
        let meta: ComposeMeta
        let photoIds: [String: String]
        let photos: [UploadPhoto]

        var uploads: [(id: String, jpeg: Data)] { photos.map { (id: $0.id, jpeg: $0.jpeg) } }
    }

    /// One prepared photo: its number in the request and its JPEG.
    struct UploadPhoto: Sendable {
        let id: String
        let jpeg: Data
    }

    private enum Step {
        case wait
        case done(Result<TriggerMemory, TriggerAttemptBox>)
        case resubmit
    }

    /// The meta's photos, read and prepared for upload (768 px, no
    /// metadata), keyed by their localIdentifiers.
    private func uploads(_ meta: ComposeMeta, photoIds: [String: String]) async -> [String: Data] {
        var prepared: [String: Data] = [:]
        let library = self.library
        for number in meta.photos.map(\.id) {
            guard let id = photoIds[number],
                  let data = await Self.first(within: Self.readTimeout, { await library.uploadData(for: id) }),
                  let jpeg = UploadImage.prepare(data) else { continue }
            prepared[id] = jpeg
        }
        return prepared
    }

    /// `meta` with only the photos that could be read, numbered P1... again.
    static func keeping(_ meta: ComposeMeta, photoIds: [String: String], read: Set<String>)
        -> (meta: ComposeMeta, photoIds: [String: String]) {
        var numbers: [String: String] = [:]
        var photos: [ComposeMeta.Photo] = []
        for photo in meta.photos {
            guard let id = photoIds[photo.id], read.contains(id) else { continue }
            let number = "P\(photos.count + 1)"
            numbers[number] = id
            photos.append(ComposeMeta.Photo(
                id: number, takenAt: photo.takenAt, labels: photo.labels, faces: photo.faces,
                favorite: photo.favorite, edited: photo.edited, represents: photo.represents
            ))
        }
        let all = photos.count == meta.photos.count
        let kept = ComposeMeta(groupKey: meta.groupKey, date: meta.date, weekday: meta.weekday,
                               startTime: meta.startTime, endTime: meta.endTime, place: meta.place,
                               rawCount: meta.rawCount, coversAll: meta.coversAll && all,
                               recentQuestionTypes: meta.recentQuestionTypes, bucket: meta.bucket, tz: meta.tz,
                               photos: photos)
        return (kept, numbers)
    }

    /// The photos read and the meta renumbered; nil when under three could be read.
    func prepare(_ meta: ComposeMeta, photoIds: [String: String]) async -> Prepared? {
        let prepared = await uploads(meta, photoIds: photoIds)
        let sent = Self.keeping(meta, photoIds: photoIds, read: Set(prepared.keys))
        guard sent.meta.photos.count >= FragmentGrouper.minimumUnique else { return nil }
        let photos = sent.meta.photos.compactMap { photo in
            sent.photoIds[photo.id].flatMap { prepared[$0] }.map { UploadPhoto(id: photo.id, jpeg: $0) }
        }
        return Prepared(meta: sent.meta, photoIds: sent.photoIds, photos: photos)
    }

    func run(_ meta: ComposeMeta, photoIds: [String: String]) async -> Result<Composed, TriggerAttemptBox> {
        guard let sent = await prepare(meta, photoIds: photoIds) else {
            return .failure(TriggerAttemptBox(.rejected(Self.unreadableMessage)))
        }
        return await compose(sent.meta, photos: sent.uploads).map { Composed(memory: $0, photoIds: sent.photoIds) }
    }

    private func compose(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)])
        async -> Result<TriggerMemory, TriggerAttemptBox> {
        var waited: TimeInterval = 0
        var resubmitted = false
        var transportFailures = 0
        var jobId: String
        switch await submit(meta, photos: photos, waited: &waited) {
        case .success(let id): jobId = id
        case .failure(let box): return .failure(box)
        }
        // A cancelled task's sleeps return at once: stop instead of polling nonstop.
        while waited < Self.budget, !Task.isCancelled {
            try? await sleep(Self.pollInterval)
            waited += Self.pollInterval
            switch await pollOnce(jobId, waited: &waited, transportFailures: &transportFailures) {
            case .wait:
                continue
            case .done(let result):
                return result
            case .resubmit:
                guard !resubmitted else { return .failure(TriggerAttemptBox(.stop(.aiTimeout))) }
                resubmitted = true
                switch await submit(meta, photos: photos, waited: &waited) {
                case .success(let id): jobId = id
                case .failure(let box): return .failure(box)
                }
            }
        }
        return .failure(TriggerAttemptBox(.stop(.aiTimeout)))
    }

    private func pollOnce(_ jobId: String, waited: inout TimeInterval, transportFailures: inout Int) async -> Step {
        let status: ComposeJobStatus
        do {
            status = try await client.poll(jobId)
            transportFailures = 0
        } catch ComposeError.rateLimited {
            try? await sleep(Self.rateLimitWait)
            waited += Self.rateLimitWait
            return .wait
        } catch ComposeError.unreachable {
            transportFailures += 1
            guard transportFailures >= Self.transportRetries else { return .wait }
            return .done(.failure(TriggerAttemptBox(.stop(.backendUnreachable))))
        } catch {
            return .done(.failure(TriggerAttemptBox(.stop(Self.failure(for: error)))))
        }
        switch status {
        case .running: return .wait
        case .ok(let memory): return .done(.success(memory))
        case .rejected(_, let message): return .done(.failure(TriggerAttemptBox(.rejected(message))))
        case .failed(let reason, let message):
            return .done(.failure(TriggerAttemptBox(.stop(reason == "timeout" ? .aiTimeout : .backend(message)))))
        case .expired: return .resubmit
        }
    }

    /// The job id. No connection is tried again, 5 s apart, three times in all.
    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)], waited: inout TimeInterval)
        async -> Result<String, TriggerAttemptBox> {
        var transportFailures = 0
        // A cancelled task's sleeps return at once: stop instead of polling nonstop.
        while waited < Self.budget, !Task.isCancelled {
            do {
                return .success(try await client.submit(meta, photos: photos))
            } catch ComposeError.rateLimited {
                try? await sleep(Self.rateLimitWait)
                waited += Self.rateLimitWait
            } catch ComposeError.unreachable {
                transportFailures += 1
                guard transportFailures < Self.transportRetries else {
                    return .failure(TriggerAttemptBox(.stop(.backendUnreachable)))
                }
                try? await sleep(Self.pollInterval)
                waited += Self.pollInterval
            } catch {
                return .failure(TriggerAttemptBox(.stop(Self.failure(for: error))))
            }
        }
        return .failure(TriggerAttemptBox(.stop(.aiTimeout)))
    }

    /// `work`'s answer, or nil when it takes longer than `seconds` (PhotoKit
    /// may never answer for a photo it cannot fetch).
    static func first<Value: Sendable>(within seconds: TimeInterval,
                                       _ work: @escaping @Sendable () async -> Value?) async -> Value? {
        await withCheckedContinuation { continuation in
            let once = OnceContinuation(continuation)
            Task { once.resume(await work()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(nil)
            }
        }
    }

    static func failure(for error: Error) -> TriggerFailure {
        switch error as? ComposeError {
        case .unreachable, .none: return .backendUnreachable
        case .unauthorized: return .unauthorized
        case .badRequest(let message): return .backend(message)
        case .rateLimited: return .aiTimeout
        case .server(let status): return .backend("HTTP \(status)")
        }
    }
}

/// `ComposeSession.first(within:)` for the app: async work that may never
/// answer (PhotoKit, an iCloud download), bounded.
public enum TimeLimit {
    /// `work`'s answer, or nil when it takes longer than `seconds`. `work`
    /// is not cancelled; its late answer is dropped.
    public static func first<Value: Sendable>(within seconds: TimeInterval,
                                              _ work: @escaping @Sendable () async -> Value?) async -> Value? {
        await ComposeSession.first(within: seconds, work)
    }
}

/// Resumes a continuation once, whoever comes first.
private final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value?) {
        let pending = lock.withLock { () -> CheckedContinuation<Value?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
