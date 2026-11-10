import SwiftUI
import UIKit

/// What the last "Preview the scheduled push" press said, when it is not a
/// progress step. Shared by Home's debug card and the debug screen.
struct TriggerNoticeLine: View {
    let notice: TriggerController.Notice

    var body: some View {
        let text: Text = switch notice {
        case .nothingScheduled: Text("Nothing is scheduled right now")
        case .notificationsOff: Text("Notifications are off")
        case .previewSent(let day): Text("The push for \(day) comes in 10 s")
        }
        return text
            .font(.miraCaption)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityIdentifier("trigger.notice")
    }
}

/// The steps of the current "Try a group outside the schedule" press.
struct TriggerProgressList: View {
    let controller: TriggerController
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(controller.steps.enumerated()), id: \.offset) { _, step in
                TriggerProgressText(step: step)
            }
            if case .askingAI = controller.steps.last {
                // The push comes 10 s after the AI answers, which takes about a
                // minute; a tester who locks the phone would wait forever.
                Text("Please stay here, about a minute")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.ink)
            }
            if needsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("trigger.openSettings")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trigger.progress")
    }

    private var needsSettings: Bool {
        switch controller.steps.last {
        case .failed(.notificationsOff), .failed(.photosDenied): return true
        default: return false
        }
    }
}
