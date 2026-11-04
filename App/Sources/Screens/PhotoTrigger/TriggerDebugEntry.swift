import MiraNoteKit
import SwiftUI
import UIKit

/// Home's debug entry for the photo trigger, at the foot of the page in
/// development and TestFlight builds (handoff 7.5): preview the scheduled
/// push, try a group outside the schedule, the fake-AI switch, and the
/// press's progress under them.
struct TriggerDebugEntry: View {
    @Bindable var controller: TriggerController
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo trigger (test)")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }

            Toggle(isOn: $controller.fakeAI) {
                Text("Fake AI")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
            }
            .disabled(controller.isRunning)
            .accessibilityIdentifier("trigger.fakeAI")

            if let notice = controller.notice {
                noticeText(notice)
            }
            if !controller.steps.isEmpty {
                progress
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.imageCorner)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    @ViewBuilder private var buttons: some View {
        Button("Preview the scheduled push") { controller.previewNext() }
            .buttonStyle(SoftPill())
            .disabled(controller.isRunning)
            .accessibilityIdentifier("trigger.preview")
        Button("Try a group outside the schedule") { controller.tryOutside() }
            .buttonStyle(SoftPill())
            .disabled(controller.isRunning)
            .accessibilityIdentifier("trigger.tryOutside")
    }

    private func noticeText(_ notice: TriggerController.Notice) -> some View {
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

    private var progress: some View {
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
