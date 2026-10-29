import ImageIO
import MiraNoteKit
import UniformTypeIdentifiers
import UserNotifications

/// The photo trigger's local push (v0, fired from the Home demo entry): the
/// memory's title and body with its cover photo attached, three seconds out.
/// A tap only opens the app -- no routing yet.
enum TriggerNotifications {
    enum Outcome {
        case scheduled, denied, failed
    }

    /// Asks for permission (the system prompt appears the first time only),
    /// then schedules the push.
    static func schedule(_ memory: TriggerMemory, from source: TriggerMemorySource) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = memory.push.title
        content.body = memory.push.body
        content.interruptionLevel = .active
        if let cover = memory.coverPhoto, let url = source.url(for: cover), let attachment = attachment(from: url) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "trigger-\(memory.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed
        }
    }

    /// The system moves an attachment's file into its own store, so it must
    /// not be the bundled photo: a ~1000 px JPEG copy in the temporary folder.
    private static func attachment(from url: URL) -> UNNotificationAttachment? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("trigger-cover-\(UUID().uuidString).jpg")
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, type, 1, nil) else { return nil }
        let quality = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, quality)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return try? UNNotificationAttachment(identifier: "cover", url: file)
    }
}

/// Shows the push as a banner while the app is in front (the system hides
/// foreground notifications otherwise). Installed once at launch.
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

    /// v0: a tap just brings the app forward.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {}
}
