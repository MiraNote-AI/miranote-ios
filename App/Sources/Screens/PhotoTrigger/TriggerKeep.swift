import Foundation
import MiraNoteKit
import Observation

/// The ending's button, from the story to its canvas draft (handoff 7.8).
/// The draft is made while the story stays up, and it opens only over the
/// story that asked for it: closed meanwhile, or given way to another
/// cover, the draft is dropped and nothing the writer opened is closed.
/// While the story's cover gives way to the draft's, no push opens: Home
/// is bare for that pause, and a story opened in it would be lost.
@MainActor
@Observable
final class TriggerKeep {
    /// HomeFlow's covers as the keep needs them.
    struct Covers {
        /// The story on screen now (`TriggerOpening.id`); nil when the
        /// cover is anything else, or there is none.
        let story: () -> UUID?
        /// No cover is up.
        let isEmpty: () -> Bool
        let close: () -> Void
        let open: (TriggerDraft) -> Void
        /// A draft that will not open: what it saved is not needed.
        let discard: (TriggerDraft) -> Void
    }

    /// The story's cover is gone before the draft's comes up.
    private let gap: Duration
    /// From the story's close to the draft's open.
    private(set) var switching = false

    init(gap: Duration = .milliseconds(300)) {
        self.gap = gap
    }

    /// Whether a pending push may open its story now.
    func mayOpenPush(coverUp: Bool) -> Bool { !coverUp && !switching }

    /// `make`s the draft of `story`, then swaps the story's cover for it.
    func keep(_ story: UUID, make: () async -> TriggerDraft, covers: Covers) async {
        let draft = await make()
        guard covers.story() == story else { return covers.discard(draft) }
        switching = true
        defer { switching = false }
        covers.close()
        try? await Task.sleep(for: gap)
        // A page opened in the pause is the writer's: it stays.
        guard covers.isEmpty() else { return covers.discard(draft) }
        covers.open(draft)
    }
}
