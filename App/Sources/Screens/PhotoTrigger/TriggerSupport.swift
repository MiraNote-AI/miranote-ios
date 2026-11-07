import Foundation
import Photos
import UserNotifications

/// The first-launch prompts, in order: Photos, then notifications, each only
/// while the system has not been asked (handoff G5).
struct TriggerPermissions: Sendable {
    var photosUndecided: @Sendable () -> Bool
    var askPhotos: @Sendable () async -> Void
    var notificationsUndecided: @Sendable () async -> Bool
    var askNotifications: @Sendable () async -> Void

    func askFirstLaunch() async {
        if photosUndecided() { await askPhotos() }
        if await notificationsUndecided() { await askNotifications() }
    }

    static let live = TriggerPermissions(
        photosUndecided: { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined },
        askPhotos: { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) },
        notificationsUndecided: {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
        },
        askNotifications: {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    )

    /// Nothing is asked (UI tests that keep their Home as it was).
    static let none = TriggerPermissions(
        photosUndecided: { false }, askPhotos: {}, notificationsUndecided: { false }, askNotifications: {}
    )
}

/// Async work the calling thread waits for, but never longer than a limit.
enum BoundedWait {
    /// What a background-time expiry handler gives the scheduler: a quick
    /// actor hop and two small file writes fit well inside.
    static let expiryGrace: TimeInterval = 0.5

    /// Starts `work` off the calling thread and blocks for it at most
    /// `limit` seconds; true when it finished in time. `work` is never
    /// cancelled: it may finish after this returns.
    @discardableResult
    static func run(atMost limit: TimeInterval, _ work: @escaping @Sendable () async -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await work()
            done.signal()
        }
        return done.wait(timeout: .now() + limit) == .success
    }
}

/// The switch as the run reads it, off the main actor.
final class FakeAIFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The trigger's content words (push, question, button, bucket) are
/// Chinese whatever the app language (handoff 7.0): read from the built
/// zh-Hans table, falling back to the key.
enum TriggerContent {
    private static let table: Bundle? = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init)

    @Sendable static func zh(_ key: String) -> String {
        table?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }
}
