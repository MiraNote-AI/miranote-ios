import Foundation

/// Asks the mood of saved pages, one request at a time, and writes each
/// answer onto the page in the library. A page is asked only when it has
/// no mood or its words changed since it was judged: a reopened jar or a
/// page saved unchanged costs no request. A failed ask leaves the mood as
/// it was, and the same words are not asked again for `retryAfter` -- an
/// offline phone costs one request per page, not one per visit.
@MainActor
public final class MoodJudge {
    private let service: MoodService
    private let library: HomeViewModel
    private let retryAfter: TimeInterval
    /// Pages saved: asked first, whatever screen shows.
    private var saved: [Memory.ID] = []
    /// Pages the star jar shows: replaced when it shows others.
    private var shown: [Memory.ID] = []
    private var failed: [Memory.ID: (textHash: String, at: Date)] = [:]
    private var worker: Task<Void, Never>?

    public init(service: MoodService, library: HomeViewModel, retryAfter: TimeInterval = 300) {
        self.service = service
        self.library = library
        self.retryAfter = retryAfter
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

    private func startIfNeeded() {
        guard worker == nil, !saved.isEmpty || !shown.isEmpty else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        while !saved.isEmpty || !shown.isEmpty {
            await ask(saved.isEmpty ? shown.removeFirst() : saved.removeFirst())
        }
        worker = nil
    }

    private func ask(_ id: Memory.ID) async {
        // The page as it is when its turn comes, not when it was queued.
        guard let page = library.memory(id) else { return }
        let text = page.moodText
        let textHash = Memory.moodHash(of: text)
        // Judged from these words already (also: asked a moment ago, when
        // it was queued twice).
        if page.mood != nil, page.moodTextHash == textHash { return }
        if let failure = failed[id], failure.textHash == textHash,
           Date.now.timeIntervalSince(failure.at) < retryAfter { return }
        if text.isEmpty {
            // Stickers or a sound alone: nothing to read a mood from.
            library.setMood(.neutral, judgedFrom: textHash, for: id)
            return
        }
        do {
            let mood = try await service.mood(for: text)
            failed[id] = nil
            library.setMood(mood, judgedFrom: textHash, for: id)
        } catch {
            failed[id] = (textHash, .now)
        }
    }
}
