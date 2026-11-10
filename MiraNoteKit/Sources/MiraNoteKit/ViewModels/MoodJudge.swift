import Foundation

/// Asks the mood of saved pages, one request at a time, and writes each
/// answer onto the page in the library. A page is asked only when it has
/// no mood or its words changed since it was judged: a reopened jar or a
/// page saved unchanged costs no request. A failed ask leaves the mood as
/// it was, and the same words are not asked again for `retryAfter` -- an
/// offline phone costs one request per page, not one per visit. An error
/// that is not about the page (offline, 401, 404, 429, 530, ...) pauses
/// the whole queue for `retryAfter` instead, and asks are spaced by `gap`:
/// the text service's per-token rate limit is shared with the text tools.
@MainActor
public final class MoodJudge {
    private let service: MoodService
    private let library: HomeViewModel
    private let retryAfter: TimeInterval
    private let gap: Duration
    /// Pages saved: asked first, whatever screen shows.
    private var saved: [Memory.ID] = []
    /// Pages the star jar shows: replaced when it shows others.
    private var shown: [Memory.ID] = []
    private var failed: [Memory.ID: (textHash: String, at: Date)] = [:]
    /// Set by an error about the service, not the page: nothing is asked
    /// before then.
    private var pausedUntil: Date?
    private var worker: Task<Void, Never>?

    public init(
        service: MoodService,
        library: HomeViewModel,
        retryAfter: TimeInterval = 300,
        gap: Duration = .milliseconds(300)
    ) {
        self.service = service
        self.library = library
        self.retryAfter = retryAfter
        self.gap = gap
    }

    /// Queues saved pages to judge; one already waiting keeps its place.
    public func judge(_ noteIDs: [Memory.ID]) {
        for id in noteIDs where !saved.contains(id) {
            saved.append(id)
        }
        startIfNeeded()
    }

    /// The pages the star jar shows now, in place of the ones it showed
    /// before: a period left, or the jar closed (`[]`), is not asked for.
    public func show(_ noteIDs: [Memory.ID]) {
        shown = noteIDs
        startIfNeeded()
    }

    private var isPaused: Bool { pausedUntil.map { Date.now < $0 } ?? false }

    private var hasQueued: Bool { !saved.isEmpty || !shown.isEmpty }

    private func startIfNeeded() {
        guard worker == nil, hasQueued, !isPaused else { return }
        worker = Task { await drain() }
    }

    /// Asks until the queues are empty or the service is paused; what is
    /// left waits for the next `judge` or `show`.
    private func drain() async {
        while hasQueued, !isPaused {
            let requested = await ask(saved.isEmpty ? shown.removeFirst() : saved.removeFirst())
            if requested, hasQueued { try? await Task.sleep(for: gap) }
        }
        worker = nil
    }

    /// Whether a request was sent.
    private func ask(_ id: Memory.ID) async -> Bool {
        // The page as it is when its turn comes, not when it was queued. A
        // draft's words are not the page's (#137): its star keeps the mood
        // the last Save got, and the next Save asks again.
        guard let page = library.memory(id), !page.isDraft else { return false }
        let text = page.moodText
        let textHash = Memory.moodHash(of: text)
        // Judged from these words already (also: asked a moment ago, when
        // it was queued twice).
        if page.mood != nil, page.moodTextHash == textHash { return false }
        if let failure = failed[id], failure.textHash == textHash,
           Date.now.timeIntervalSince(failure.at) < retryAfter { return false }
        if text.isEmpty {
            // Stickers or a sound alone: nothing to read a mood from.
            library.setMood(.neutral, judgedFrom: textHash, for: id)
            return false
        }
        do {
            let mood = try await service.mood(for: text)
            failed[id] = nil
            library.setMood(mood, judgedFrom: textHash, for: id)
        } catch where Self.isAboutTheService(error) {
            pausedUntil = Date.now.addingTimeInterval(retryAfter)
        } catch {
            failed[id] = (textHash, .now)
        }
        return true
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
