import MiraNoteKit

/// A push opened: its id, the memory with any deleted photos taken out,
/// and where its photos are in the library.
struct TriggerOpening {
    let pushId: String
    let memory: TriggerMemory
    let photoIds: [String: String]
}
