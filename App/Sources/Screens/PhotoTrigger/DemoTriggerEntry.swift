import SwiftUI

/// Home's demo entry for the photo trigger, shown in Debug builds and under
/// `-DEMO-SAMPLES`: send the push now, or open the memory straight away.
/// Without a bundled demo memory it says so instead.
struct DemoTriggerEntry: View {
    let available: Bool
    var onPush: () async -> TriggerNotifications.Outcome
    var onOpen: () -> Void

    @State private var status: LocalizedStringKey?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Demo: photo memory")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)

            if available {
                HStack(spacing: 10) {
                    Button("Push now", action: push)
                        .buttonStyle(SoftPill())
                        .disabled(sending)
                        .accessibilityIdentifier("trigger.demo.push")
                    Button("Open memory", action: onOpen)
                        .buttonStyle(SoftPill())
                        .accessibilityIdentifier("trigger.demo.open")
                }
                if let status {
                    Text(status)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text("No demo data")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.imageCorner)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func push() {
        sending = true
        Task {
            let outcome = await onPush()
            sending = false
            switch outcome {
            case .scheduled: status = "The push arrives in 3 seconds"
            case .denied: status = "Notifications are off -- allow MiraNote notifications in Settings"
            case .failed: status = "The push was not sent"
            }
        }
    }
}
