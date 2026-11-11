import Foundation

/// Asks the mood of saved pages, one request at a time, and writes each
/// answer onto the page in the library. A page is asked only when it has
/// no mood or its words changed since it was judged: a reopened jar or a
/// page saved unchanged costs no request. A failed ask leaves the mood as
/// it was, and the same words are not asked again for `retryAfter` -- an
/// page that cannot be read costs one request per `retryAfter`, not one
/// per visit. An error that is not about the page (offline, 401, 404,
/// 429, 530, ...) keeps the page at the front of its queue and pauses the
/// whole queue, which resumes by itself after each of `backoff` (#159);
/// once those are spent it waits for the next Save, jar visit or
/// `resume()`. Asks are spaced by `gap`: the text service's per-token rate
/// limit is shared with the text tools.
/// While `allowed` is false (no AI consent, or Settings' "Mood from my
/// words" off, #151) nothing is asked: queued pages wait for `resume()`.
@MainActor
public final class MoodJudge {
    private let service: MoodService
    private let library: HomeViewModel
    private let retryAfter: TimeInterval
    private let gap: Duration
    private let allowed: @MainActor () -> Bool
    private let backoff: [Duration]
    /// Pages saved: asked first, whatever screen shows.
    private var saved: [Memory.ID] = []
    /// Pages the star jar shows: replaced when it shows others.
    private var shown: [Memory.ID] = []
    private var failed: [Memory.ID: (textHash: String, at: Date)] = [:]
    /// Set by an error about the service, not the page: nothing is asked
    /// until its wake-up clears it.
    private var isPaused = false
    /// Errors about the service in a row: one more than `backoff` holds
    /// stops the queue until the next `judge`, `show` or `resume`.
    private var serviceFailures = 0
    private var worker: Task<Void, Never>?

    public init(
        service: MoodService,
        library: HomeViewModel,
        retryAfter: TimeInterval = 300,
        gap: Duration = .milliseconds(300),
        backoff: [Duration] = [.seconds(10), .seconds(60)],
        allowed: @escaping @MainActor () -> Bool = { true }
    ) {
        self.service = service
        self.library = library
        self.retryAfter = retryAfter
        self.gap = gap
        self.allowed = allowed
        self.backoff = backoff
    }

    /// Queues saved pages to judge; one already waiting keeps its place.
    public func judge(_ noteIDs: [Memory.ID]) {
        for id in noteIDs where !saved.contains(id) {
            saved.append(id)
        }
        resume()
    }

    /// The pages the star jar shows now, in place of the ones it showed
    /// before: a period left, or the jar closed (`[]`), is not asked for.
    public func show(_ noteIDs: [Memory.ID]) {
        shown = noteIDs
        resume()
    }

    /// Asks what is still queued, with fresh tries if the last ones were
    /// spent (the app came back to the foreground). Waits out a pause.
    public func resume() {
        if serviceFailures > backoff.count { serviceFailures = 0 }
        startIfNeeded()
    }

    private var hasQueued: Bool { !saved.isEmpty || !shown.isEmpty }

    /// Paused, out of tries, or not allowed to ask at all.
    private var isStopped: Bool { isPaused || serviceFailures > backoff.count || !allowed() }

    private func startIfNeeded() {
        guard worker == nil, hasQueued, !isStopped else { return }
        worker = Task { await drain() }
    }

    /// Asks until the queues are empty or the service is paused or out of
    /// tries.
    private func drain() async {
        while hasQueued, !isStopped {
            let fromSaved = !saved.isEmpty
            let id = fromSaved ? saved.removeFirst() : shown.removeFirst()
            let jar = shown
            let outcome = await ask(id)
            if outcome == .serviceDown {
                // Back at the front, unless Save queued it again meanwhile
                // or the jar moved on to other pages.
                if fromSaved, !saved.contains(id) { saved.insert(id, at: 0) }
                if !fromSaved, shown == jar { shown.insert(id, at: 0) }
                pause()
            } else if outcome == .asked, hasQueued {
                try? await Task.sleep(for: gap)
            }
        }
        worker = nil
    }

    /// Pauses for the next step of `backoff`, then resumes by itself; past
    /// the last step, stops.
    private func pause() {
        serviceFailures += 1
        guard serviceFailures <= backoff.count else { return }
        isPaused = true
        let delay = backoff[serviceFailures - 1]
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.isPaused = false
            self?.startIfNeeded()
        }
    }

    private enum Outcome { case skipped, asked, serviceDown }

    private func ask(_ id: Memory.ID) async -> Outcome {
        // The page as it is when its turn comes, not when it was queued. A
        // draft's words are not the page's (#137): its star keeps the mood
        // the last Save got, and the next Save asks again.
        guard let page = library.memory(id), !page.isDraft else { return .skipped }
        let text = page.moodText
        let textHash = Memory.moodHash(of: text)
        // Judged from these words already (also: asked a moment ago, when
        // it was queued twice).
        if page.mood != nil, page.moodTextHash == textHash { return .skipped }
        if let failure = failed[id], failure.textHash == textHash,
           Date.now.timeIntervalSince(failure.at) < retryAfter { return .skipped }
        if text.isEmpty {
            // Stickers or a sound alone: nothing to read a mood from.
            library.setMood(.neutral, judgedFrom: textHash, for: id)
            return .skipped
        }
        do {
            let mood = try await service.mood(for: text)
            failed[id] = nil
            serviceFailures = 0
            library.setMood(mood, judgedFrom: textHash, for: id)
        } catch where Self.isAboutTheService(error) {
            return .serviceDown
        } catch {
            serviceFailures = 0
            failed[id] = (textHash, .now)
        }
        return .asked
    }

    /// Errors no other page would escape: no network, no access, no
    /// endpoint, rate-limited, or the server or its tunnel down. A 502 is
    /// the server's "could not read the model's reply" -- about the page.
    private static func isAboutTheService(_ error: Error) -> Bool {
        switch error as? BackendError {
        case .unreachable, .timedOut:
            return true
        case .server(let status, _):
            return [401, 404, 429].contains(status) || (status >= 500 && status != 502)
        case .decoding, nil:
            return false
        }
    }
}
