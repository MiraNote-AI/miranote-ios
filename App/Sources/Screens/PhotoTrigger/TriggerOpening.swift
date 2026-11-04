import MiraNoteKit

/// A push opened: its id, the memory with any deleted photos taken out,
/// and where its photos are in the library.
struct TriggerOpening {
    let pushId: String
    let memory: TriggerMemory
    let photoIds: [String: String]
    /// The push bucket; nil in a record saved before phase 2.
    let bucketId: PushBucket?

    init(pushId: String, memory: TriggerMemory, photoIds: [String: String], bucketId: PushBucket? = nil) {
        self.pushId = pushId
        self.memory = memory
        self.photoIds = photoIds
        self.bucketId = bucketId
    }

    /// The bucket's name for the menu note: Chinese content, whatever the
    /// app language. An old record falls back to the name it carries.
    var bucketName: String {
        bucketId.map { TriggerContent.zh($0.catalogKey) } ?? memory.bucket
    }

    /// "Fewer like this" makes no sense for `other`; an old record has no
    /// bucket and keeps the choice (the scheduler ignores it).
    var allowsFewer: Bool { bucketId != .other }
}

/// What decides when a pending push is looked at: the push, and whether a
/// cover is on screen (it waits for that cover to close).
struct PendingPushKey: Equatable {
    let pushId: String?
    let coverUp: Bool
}
