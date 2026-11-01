import Foundation

/// One group's round trip to the backend (handoff 5): prepare the photos,
/// submit, then poll every 5 s for up to 5 minutes of waiting. A 429 waits
/// 10 s; an expired job is submitted once more; a request cut short (the
/// app went to the background) is tried again. The budget counts the
/// waits, so time spent suspended in the background does not use it up.
struct ComposeSession {
    static let pollInterval: TimeInterval = 5
    static let rateLimitWait: TimeInterval = 10
    static let budget: TimeInterval = 300
    /// Consecutive transport failures tolerated while polling.
    static let pollRetries = 3

    let deps: TriggerDependencies

    private enum Step {
        case wait
        case done(Result<TriggerMemory, TriggerAttemptBox>)
        case resubmit
    }

    /// The meta's photos, read and prepared for upload (768 px, no metadata).
    private func uploads(_ meta: ComposeMeta, photoIds: [String: String]) async -> [(id: String, jpeg: Data)] {
        var photos: [(id: String, jpeg: Data)] = []
        for number in meta.photos.map(\.id) {
            guard let id = photoIds[number], let data = await deps.library.uploadData(for: id),
                  let jpeg = UploadImage.prepare(data) else { continue }
            photos.append((number, jpeg))
        }
        return photos
    }

    func run(_ meta: ComposeMeta, photoIds: [String: String]) async -> Result<TriggerMemory, TriggerAttemptBox> {
        let photos = await uploads(meta, photoIds: photoIds)
        var waited: TimeInterval = 0
        var resubmitted = false
        var transportFailures = 0
        var jobId: String
        switch await submit(meta, photos: photos, waited: &waited) {
        case .success(let id): jobId = id
        case .failure(let box): return .failure(box)
        }
        while waited < Self.budget {
            try? await deps.sleep(Self.pollInterval)
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
            status = try await deps.client.poll(jobId)
            transportFailures = 0
        } catch ComposeError.rateLimited {
            try? await deps.sleep(Self.rateLimitWait)
            waited += Self.rateLimitWait
            return .wait
        } catch ComposeError.unreachable {
            transportFailures += 1
            guard transportFailures >= Self.pollRetries else { return .wait }
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

    /// The job id.
    private func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)], waited: inout TimeInterval)
        async -> Result<String, TriggerAttemptBox> {
        while waited < Self.budget {
            do {
                return .success(try await deps.client.submit(meta, photos: photos))
            } catch ComposeError.rateLimited {
                try? await deps.sleep(Self.rateLimitWait)
                waited += Self.rateLimitWait
            } catch {
                return .failure(TriggerAttemptBox(.stop(Self.failure(for: error))))
            }
        }
        return .failure(TriggerAttemptBox(.stop(.aiTimeout)))
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
