import MiraNoteKit
import UIKit

/// A push opened: its id, the memory with any deleted photos taken out,
/// and where its photos are in the library.
struct TriggerOpening {
    /// This opening of the push: a story opened again is another one.
    let id = UUID()
    let pushId: String
    let memory: TriggerMemory
    let photoIds: [String: String]
    /// The push bucket; nil in a record saved before phase 2.
    let bucketId: PushBucket?
    /// What `TriggerLaunchRouter.pending` said (an id or "latest"): it is
    /// cleared once the story is on screen.
    let request: String?

    init(pushId: String, memory: TriggerMemory, photoIds: [String: String], bucketId: PushBucket? = nil,
         request: String? = nil) {
        self.pushId = pushId
        self.memory = memory
        self.photoIds = photoIds
        self.bucketId = bucketId
        self.request = request
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

/// What UIKit shows over the app's root: an alert or a sheet on Home, or
/// a cover still on its way out. A full-screen cover asked for meanwhile
/// never appears.
enum RootPresentation {
    @MainActor static var isUp: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    /// Returns once nothing is presented over the root; false if the task
    /// was cancelled first.
    @MainActor static func waitUntilBare(every interval: Duration = .milliseconds(300)) async -> Bool {
        while isUp {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return false }
        }
        return !Task.isCancelled
    }
}

/// What decides when a pending push is looked at: the push, and whether a
/// cover is on screen (it waits for that cover to close).
struct PendingPushKey: Equatable {
    let pushId: String?
    let coverUp: Bool
}
