import ImageIO
import MiraNoteKit
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// The photo trigger's local push (handoff 7.6): the record is saved
/// first, the notification carries only its `pushId` (also its
/// identifier), the title and body are the memory's, the cover is the peak
/// photo, ten seconds out.
struct LiveTriggerNotifier: PushNotificationCenter {
    let photos: TriggerPhotoProviding
    static let delay: TimeInterval = 10
    static let thread = "photo-trigger"

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    func isAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func pending() async -> Set<String> {
        Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
    }

    func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers.filter(PushIdentifier.isOurs))
    }

    func removeDelivered(_ identifiers: [String]) async {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: identifiers.filter(PushIdentifier.isOurs))
    }

    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = record.memory.push.title
        content.body = record.memory.push.body
        content.interruptionLevel = .active
        content.threadIdentifier = Self.thread
        content.userInfo = ["pushId": record.pushId]
        if let cover = record.memory.coverPhoto, let id = record.photoIds[cover.id],
           let image = await photos.image(for: id, maxPixel: 1000, allowNetwork: true),
           let attachment = Self.attachment(image) {
            content.attachments = [attachment]
        }
        content.relevanceScore = relevance
        let trigger: UNNotificationTrigger = at.map { UNCalendarNotificationTrigger(dateMatching: $0, repeats: false) }
            ?? UNTimeIntervalNotificationTrigger(timeInterval: Self.delay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    /// The system moves an attachment's file into its own store: a ~1000 px
    /// JPEG copy in the temporary folder.
    private static func attachment(_ image: UIImage) -> UNNotificationAttachment? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("trigger-cover-\(UUID().uuidString).jpg")
        guard (try? data.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "cover", url: file)
    }
}

/// Shows the push as a banner while the app is in front (the system hides
/// foreground notifications otherwise), and hands a tap's `pushId` to the
/// router -- from the lock screen, the banner, or a launch the tap caused.
/// Installed once at launch.
final class TriggerNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TriggerNotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // The completion-handler forms, completed on the main thread: the async
    // forms finish on a background thread, and UIKit asserts when a tap
    // that launched the app completes there (a crash on every cold launch
    // from a push, found 2026-11-01).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async { completionHandler([.banner, .list]) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let pushId = response.notification.request.content.userInfo["pushId"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let pushId { TriggerLaunchRouter.shared.pending = pushId }
            }
            completionHandler()
        }
    }
}
