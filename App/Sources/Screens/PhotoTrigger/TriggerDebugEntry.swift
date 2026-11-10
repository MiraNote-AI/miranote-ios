import MiraNoteKit
import SwiftUI

/// Home's debug entry for the photo trigger, at the foot of the page in
/// development and TestFlight builds (handoff 7.5): preview the scheduled
/// push, try a group outside the schedule, the fake-AI switch, and the
/// press's progress under them.
struct TriggerDebugEntry: View {
    @Bindable var controller: TriggerController

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
                TriggerNoticeLine(notice: notice)
            }
            if !controller.steps.isEmpty {
                TriggerProgressList(controller: controller)
            }
            // A plain link: it needs nothing from Home's navigation path.
            NavigationLink {
                TriggerDebugScreen(controller: controller)
            } label: {
                Text("All details")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 34)
                    .background(Palette.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trigger.allDetails")
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
}
