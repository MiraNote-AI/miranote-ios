import ImageIO
import MiraNoteKit
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// The photo trigger's local push (handoff 7.6): the record is saved
/// first, the notification carries only its `pushId` (also its
/// identifier), the title and body are the memory's, the cover is the peak
/// photo, ten seconds out.
struct LiveTriggerNotifier: TriggerNotifying {
    let photos: TriggerPhotoProviding
    static let delay: TimeInterval = 10
    static let thread = "photo-trigger"

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    func schedule(_ record: PushRecord) async -> Bool {
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
        let request = UNNotificationRequest(
            identifier: record.pushId, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.delay, repeats: false)
        )
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let pushId = response.notification.request.content.userInfo["pushId"] as? String else { return }
        await MainActor.run { TriggerLaunchRouter.shared.pending = pushId }
    }
}
