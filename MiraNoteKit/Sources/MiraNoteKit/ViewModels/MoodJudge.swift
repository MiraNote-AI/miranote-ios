import Foundation

/// Asks the mood of saved pages, one request at a time, and writes each
/// answer onto the page in the library. A page saved again is asked again
/// (its words may have changed). A failed ask leaves the mood as it was --
/// nil is retried the next time the star jar shows that page.
@MainActor
public final class MoodJudge {
    private let service: MoodService
    private let library: HomeViewModel
    private var queue: [Memory.ID] = []
    private var worker: Task<Void, Never>?

    public init(service: MoodService, library: HomeViewModel) {
        self.service = service
        self.library = library
    }

    /// Queues pages to judge; one already waiting keeps its place.
    public func judge(_ noteIDs: [Memory.ID]) {
        for id in noteIDs where !queue.contains(id) {
            queue.append(id)
        }
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            // The page as it is when its turn comes, not when it was queued.
            guard let text = library.memory(id)?.moodText else { continue }
            if text.isEmpty {
                // Stickers or a sound alone: nothing to read a mood from.
                library.setMood(.neutral, for: id)
            } else if let mood = try? await service.mood(for: text) {
                library.setMood(mood, for: id)
            }
        }
        worker = nil
    }
}
