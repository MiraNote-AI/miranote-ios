import SwiftUI

/// Home's demo entry for the photo trigger, shown in Debug builds and under
/// `-DEMO-SAMPLES`: send the push now, or open the memory straight away.
/// Without a bundled demo memory it says so instead.
struct DemoTriggerEntry: View {
    let available: Bool
    var onPush: () async -> TriggerNotifications.Outcome
    var onOpen: () -> Void

    @State private var status: String?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TriggerCopy.demoTitle)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)

            if available {
                HStack(spacing: 10) {
                    Button(TriggerCopy.pushNow, action: push)
                        .buttonStyle(SoftPill())
                        .disabled(sending)
                        .accessibilityIdentifier("trigger.demo.push")
                    Button(TriggerCopy.openMemory, action: onOpen)
                        .buttonStyle(SoftPill())
                        .accessibilityIdentifier("trigger.demo.open")
                }
                if let status {
                    Text(status)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text(TriggerCopy.noDemoData)
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
            case .scheduled: status = TriggerCopy.pushScheduled
            case .denied: status = TriggerCopy.pushDenied
            case .failed: status = TriggerCopy.pushFailed
            }
        }
    }
}
