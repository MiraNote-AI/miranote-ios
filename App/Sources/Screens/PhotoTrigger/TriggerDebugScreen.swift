import MiraNoteKit
import SwiftUI

/// The tester's page that shows every step of the automatic scheduling
/// (handoff 6.8): previews, the schedule, the log, the grouping, blocked
/// days, the ledger copy, replan, clear, the category report. Development
/// and TestFlight builds only (the caller gates it like Home's debug card).
struct TriggerDebugScreen: View {
    let controller: TriggerController
    @State private var model: TriggerDebugModel
    @State private var confirmClear = false

    init(controller: TriggerController) {
        self.controller = controller
        _model = State(initialValue: TriggerDebugModel(scheduler: controller.scheduler))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                previewSection
                tryOutsideSection
                TriggerScheduledSection(snapshot: model.snapshot)
                TriggerLogSection(snapshot: model.snapshot)
                groupingLink
                TriggerBlockedSection(model: model)
                actionsSection
                categoryLink
            }
            .padding(Metrics.chromeInset)
        }
        .background(Palette.paper)
        .navigationTitle("Photo trigger details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("debug.screen")
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .onChange(of: controller.isRunning) { _, _ in Task { await model.refresh() } }
        .task(id: model.snapshot?.isRunning ?? false) {
            // A run in flight (a replan, or the app coming to the front) changes the page.
            while model.snapshot?.isRunning == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
        .confirmationDialog("Clear everything?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Yes, clear everything", role: .destructive) { Task { await model.clearAll() } }
        } message: {
            Text("Scheduled pushes, the ledger, the log and what you chose in the menu are removed.")
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        TriggerDebugSection(id: "preview", title: "Preview the scheduled push") {
            Button("Preview the scheduled push") { controller.previewNext() }
                .buttonStyle(SoftPill())
                .disabled(controller.isRunning)
                .accessibilityIdentifier("debug.preview")
            if let notice = controller.notice {
                TriggerNoticeLine(notice: notice)
            }
        }
    }

    private var tryOutsideSection: some View {
        TriggerDebugSection(id: "tryOutside", title: "Try a group outside the schedule") {
            Button("Try a group outside the schedule") { controller.tryOutside() }
                .buttonStyle(SoftPill())
                .disabled(controller.isRunning)
                .accessibilityIdentifier("debug.tryOutside")
            if !controller.steps.isEmpty {
                TriggerProgressList(controller: controller)
            }
        }
    }

    private var actionsSection: some View {
        TriggerDebugSection(id: "actions", title: "Ledger and actions") {
            Button("Copy the ledger") { Task { await model.copyLedger() } }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("debug.copyLedger")
            if model.copied {
                Text("Copied")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("debug.copied")
            }
            Button("Replan") { Task { await model.replan() } }
                .buttonStyle(SoftPill())
                .disabled(model.isReplanning)
                .accessibilityIdentifier("debug.replan")
            if model.isReplanning {
                Text("Planning...")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Button("Clear everything", role: .destructive) { confirmClear = true }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("debug.clear")
        }
    }

    private var groupingLink: some View {
        let count = model.snapshot?.groups.count ?? 0
        return NavigationLink {
            TriggerGroupingScreen(controller: controller, model: model)
        } label: {
            TriggerDebugLinkRow(title: "Grouping results", detail: String(appCopy: "Groups: \(count)"))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("debug.section.grouping")
    }

    private var categoryLink: some View {
        NavigationLink {
            TriggerCategoryScreen(controller: controller, model: model)
        } label: {
            TriggerDebugLinkRow(title: "Category report", detail: nil)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("debug.section.category")
    }
}

/// A collapsible card with a title.
struct TriggerDebugSection<Content: View>: View {
    let id: String
    let title: LocalizedStringKey
    @State private var open: Bool
    @ViewBuilder let content: Content

    init(id: String, title: LocalizedStringKey, open: Bool = true, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        _open = State(initialValue: open)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { open.toggle() } label: {
                HStack {
                    Text(title).font(.miraLabel).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("debug.section.\(id)")
            .accessibilityValue(open ? Text("expanded") : Text("collapsed"))
            if open { content }
        }
        .debugCard()
    }
}

/// The card that opens a sub-screen.
struct TriggerDebugLinkRow: View {
    let title: LocalizedStringKey
    let detail: String?

    var body: some View {
        HStack {
            Text(title).font(.miraLabel).foregroundStyle(Palette.ink)
            Spacer()
            if let detail {
                Text(detail).font(.miraCaption).foregroundStyle(Palette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
        }
        .debugCard()
    }
}

extension View {
    /// The debug card look: Home's dashed card, filled.
    func debugCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.warmWhite, in: RoundedRectangle(cornerRadius: Metrics.imageCorner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.imageCorner)
                    .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

/// Errors in the log and on the page.
extension Color {
    static let debugError = Color(hex: 0xB3261E)
}
