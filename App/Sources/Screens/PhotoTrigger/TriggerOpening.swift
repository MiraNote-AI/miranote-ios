import MiraNoteKit

/// A push opened: its id, the memory with any deleted photos taken out,
/// and where its photos are in the library.
struct TriggerOpening {
    let pushId: String
    let memory: TriggerMemory
    let photoIds: [String: String]
}

/// What decides when a pending push is looked at: the push, and whether a
/// cover is on screen (it waits for that cover to close).
struct PendingPushKey: Equatable {
    let pushId: String?
    let coverUp: Bool
}
