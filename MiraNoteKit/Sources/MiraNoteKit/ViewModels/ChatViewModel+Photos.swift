import Foundation

// The chat composer's staged photos (its own file for the ChatViewModel
// size cap).

// MARK: - Photos

extension ChatViewModel {
    public func stageImage(_ data: Data) {
        guard canStageMoreImages else { return }
        staged.append(StagedPhoto(data: data))
    }

    /// Picks from the system picker, loading side by side and staged in
    /// pick order within their batch -- a batch never waits for another:
    /// each counts toward the four while it loads, Send waits for them, and
    /// one that fails -- or is still not there after `pickTimeout` -- says
    /// so instead of vanishing. A pick removed while it loads is dropped
    /// when it arrives; cancelling the staging drops its picks at once.
    public func stagePhotos(_ loaders: [@Sendable () async -> Data?]) async {
        let room = Self.maxStagedImages - staged.count - loadingImages
        let accepted = Array(loaders.prefix(max(0, room)))
        let ids = accepted.map { _ in UUID() }
        let batch = UUID()
        for id in ids { pickBatches[id] = batch }
        loadingPicks += ids
        let timeout = pickTimeout
        await withTaskGroup(of: Void.self) { group in
            for (id, load) in zip(ids, accepted) {
                group.addTask {
                    let data = await Self.load(load, within: timeout)
                    if Task.isCancelled {
                        await self.removeLoadingPick(id)
                    } else {
                        await self.pickArrived(id, data)
                    }
                }
            }
        }
    }

    private func pickArrived(_ id: UUID, _ data: Data?) {
        // Removed while it loaded: dropped.
        guard loadingPicks.contains(id) else { return }
        arrivedPicks[id] = data
        stageArrivedPicks()
    }

    /// Stages each batch's arrived run at its front, so the order within a
    /// batch is the pick's; a removed pick no longer holds the ones after it,
    /// and a batch's stuck pick holds nothing of another batch.
    private func stageArrivedPicks() {
        var waiting: Set<UUID> = []
        for id in loadingPicks {
            guard let batch = pickBatches[id], !waiting.contains(batch) else { continue }
            guard let data = arrivedPicks.removeValue(forKey: id) else {
                waiting.insert(batch)
                continue
            }
            loadingPicks.removeAll { $0 == id }
            pickBatches[id] = nil
            if let data {
                staged.append(StagedPhoto(data: data))
            } else {
                hint = .photoNotLoaded
            }
        }
    }

    /// One pick's bytes, or nil when it fails or outlasts `timeout` -- on
    /// time even when the loader does not stop on cancellation: it is left
    /// to finish on its own. Cancelled, it gives up at once.
    private nonisolated static func load(
        _ load: @escaping @Sendable () async -> Data?,
        within timeout: Duration
    ) async -> Data? {
        let first = FirstResult()
        let loader = Task { first.resume(await load()) }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            loader.cancel()
            first.resume(nil)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { first.wait($0) }
        } onCancel: {
            timer.cancel()
        }
    }

    public func removeStagedImage(at index: Int) {
        guard staged.indices.contains(index) else { return }
        staged.remove(at: index)
    }

    /// The loading placeholder's remove: Send no longer waits for it.
    public func removeLoadingPick(_ id: UUID) {
        loadingPicks.removeAll { $0 == id }
        arrivedPicks[id] = nil
        pickBatches[id] = nil
        stageArrivedPicks()
    }

    /// The chat closed: its sent photos lived only for the transcript.
    public func discardSentPhotos() {
        for fileName in messages.flatMap(\.imageFileNames) {
            imageStore.delete(fileName: fileName)
        }
    }
}

/// A pick's result: whichever of its load and its timeout ends first,
/// handed to the waiter once -- also when it came before the wait began.
private final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    /// Nil until the first result; then that result (itself maybe nil).
    private var result: Data??

    func wait(_ continuation: CheckedContinuation<Data?, Never>) {
        lock.lock()
        guard let result else {
            self.continuation = continuation
            lock.unlock()
            return
        }
        lock.unlock()
        continuation.resume(returning: result)
    }

    func resume(_ data: Data?) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = .some(data)
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: data)
    }
}
