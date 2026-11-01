import MiraNoteKit
import SwiftUI
import UIKit

/// Home's debug entry for the photo trigger, at the foot of the page in
/// development and TestFlight builds (handoff 7.5): push the top-ranked
/// group in 10 s, push the next group, the fake-AI switch, and the press's
/// progress under them.
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
        Button("Push one in 10 s") { controller.push(next: false) }
            .buttonStyle(SoftPill())
            .disabled(controller.isRunning)
            .accessibilityIdentifier("trigger.pushTop")
        Button("Push the next group") { controller.push(next: true) }
            .buttonStyle(SoftPill())
            .disabled(controller.isRunning)
            .accessibilityIdentifier("trigger.pushNext")
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(controller.steps.enumerated()), id: \.offset) { _, step in
                TriggerProgressText(step: step)
            }
            if case .askingAI = controller.steps.last {
                // The button says "in 10 s", but the AI takes about a minute
                // first; a tester who locks the phone would wait forever.
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
