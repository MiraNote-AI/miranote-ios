import MiraNoteKit
import SwiftUI

/// A Background second-level item with a row of its own (P1A). Tidy has
/// none: a tap starts it.
enum BackgroundRow: String {
    case sets, color, paper
}

// MARK: - Background slot

extension CanvasScene {
    /// The Background tool's one row in the tool slot (REQ 11-18 overlay
    /// rule): Back and the Sets / Color / Paper / Tidy capsules (P1A), or
    /// the chosen item's row with its own Back in their place -- never two
    /// stacked. The slot keeps the tool bar's 40; a taller row stays
    /// centered on its line, rising over the card's foot, and the card
    /// never resizes. The painting's status, or why it did not come, shows
    /// one line above the row (G25).
    var backgroundSlot: some View {
        ZStack {
            HStack(spacing: 8) {
                if let row = backgroundRow {
                    TextBackKey(identifier: "background.row.back", size: 40) { showBackgroundRow(nil) }
                    BackgroundRowView(
                        row: row,
                        editor: editor,
                        painting: applyingBackground,
                        onCustomColor: openPageColorSheet
                    )
                } else {
                    TextBackKey(identifier: "background.back", size: 40, onBack: closeBackground)
                    BackgroundTools(
                        // Mira is busy painting: the tidy would be dropped.
                        tidyEnabled: editor.items.count >= 2 && !applyingBackground,
                        onSelect: showBackgroundRow,
                        onTidy: tidyFromBackground
                    )
                }
            }
            // A near miss above a short Back stays in the tool, off the page.
            .contentShape(Rectangle())
            .overlay(alignment: .top) { backgroundCaption }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Background"))
            .accessibilityIdentifier("background.row.\(backgroundRow?.rawValue ?? "tools")")
            .id(backgroundRow)
            .transition(slotLevelTransition)
        }
        .frame(height: 40)
        .padding(.horizontal, Metrics.toolBarInset)
        // VoiceOver's two-finger scrub goes up one level, as Back does.
        .accessibilityAction(.escape) {
            if backgroundRow != nil { showBackgroundRow(nil) } else { closeBackground() }
        }
    }

    /// One line above the row, taking no room (G25).
    @ViewBuilder private var backgroundCaption: some View {
        Group {
            if applyingBackground {
                Text("Painting a background for this page...")
                    .foregroundStyle(Palette.forest)
                    .accessibilityIdentifier("background.status")
            } else if let backgroundNotice {
                Text(backgroundNotice)
                    .foregroundStyle(Color(hex: 0x8C4A3A))
                    .accessibilityIdentifier("background.notice")
            }
        }
        .font(.miraCaption)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Its foot 6 above the row's top; a tap there is the page's.
        .alignmentGuide(.top) { $0[.bottom] + 6 }
        .allowsHitTesting(false)
    }

    /// An item's row in the slot, or the four items for nil.
    func showBackgroundRow(_ row: BackgroundRow?) {
        // A tall row would crowd a card shrunk by Apply's keyboard.
        applyFocus = false
        slotDeeper = row != nil
        withAnimation(.easeOut(duration: 0.22)) { backgroundRow = row }
    }

    /// Back up from the four items, Apply, or a tap on the blank page: the
    /// tool bar settles back in.
    func closeBackground() {
        enterSlot()
        backgroundPanelOpen = false
    }

    /// The row the dock now swaps in enters on the next turn (D7A).
    func enterSlot() {
        slotEntering = true
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.22)) { slotEntering = false }
        }
    }

    /// One tap re-lays the page out through Mira's normal turn (Stop,
    /// result sheet, Revert), as the "Tidy the layout" chip does (G22).
    private func tidyFromBackground() {
        // Never cancel a running turn by starting another.
        guard !mira.isWorking else { return }
        closeBackground()
        mira.askSuggestion(MiraCanvasCoordinator.tidyChip, editor: editor)
    }
}

// MARK: - Second level

/// Sets, Color, Paper and Tidy: icon-only capsules like the tool bar's (P1A).
private struct BackgroundTools: View {
    let tidyEnabled: Bool
    let onSelect: (BackgroundRow) -> Void
    let onTidy: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            item(String(appCopy: "Sets"), id: "sets", icon: Image(systemName: "swatchpalette")) { onSelect(.sets) }
            item(String(appCopy: "Color"), id: "color", icon: Image(systemName: "drop")) { onSelect(.color) }
            item(String(appCopy: "Page type"), id: "paper", icon: Image(systemName: "doc.plaintext")) {
                onSelect(.paper)
            }
            item(String(appCopy: "Ask Mira to tidy"), id: "tidy", icon: Image("background.oneTap"), action: onTidy)
                .disabled(!tidyEnabled)
                .opacity(tidyEnabled ? 1 : 0.4)
        }
    }

    private func item(_ label: String, id: String, icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ToolCapsule {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("background.tool.\(id)")
    }
}

// MARK: - Third level

/// An item's row in a glass tray, centered on the tool bar's line: Sets and
/// Color are snap rows that apply on settle or tap (Q5A), Paper a row of
/// four tiles that apply on tap (F5B, H4A). One undo step each.
private struct BackgroundRowView: View {
    let row: BackgroundRow
    @Bindable var editor: CanvasViewModel
    /// While Apply paints the color controls rest: a color set now would
    /// wipe the paid painting when it lands.
    let painting: Bool
    let onCustomColor: (PageColorRequest) -> Void

    /// The handoff's page colors (screen 05), stored as "#RRGGBB".
    static let pageSwatches: [(hex: String, name: String)] = [
        ("#F6F4E8", "Paper"), ("#F4E0D1", "Blush"), ("#D6E3D4", "Sage"),
        ("#D1E0F0", "Sky"), ("#E6D9F0", "Lilac")
    ]

    var body: some View {
        switch row {
        case .sets: setsRow
        case .color: PageColorRow(editor: editor, painting: painting, onCustomColor: onCustomColor)
        case .paper: paperRow
        }
    }

    // MARK: Sets

    /// Mini page cards (P5A), opened on the set the page wears. 64 tall: it
    /// rises over the card's foot.
    private var setsRow: some View {
        let sets = CuratedSet.all
        let worn = editor.wornCuratedSet()?.id
        return SnapRow(
            ids: sets.map(\.id), selected: worn, cellWidth: 44, spacing: 8,
            identifier: { "background.set.\($0)" },
            onApply: { id in
                if let set = sets.first(where: { $0.id == id }) { editor.applyCuratedSet(set) }
            },
            cell: { id in
                if let set = sets.first(where: { $0.id == id }) {
                    CuratedSetCard(set: set, worn: id == worn)
                        .frame(width: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel(CuratedSetLook.look(for: set).displayLabel)
                }
            }
        )
        .frame(height: 64)
        .background(BackgroundTray())
        // A set would wipe the painting on its way (R5A).
        .disabled(painting)
        .opacity(painting ? 0.45 : 1)
    }

    // MARK: Paper

    /// Blank, Grid, Lined and Dot spread across the tray; a tap applies.
    private var paperRow: some View {
        HStack(spacing: 0) {
            ForEach(PaperKind.allCases, id: \.self) { kind in
                let selected = editor.memory.paper == kind
                Button {
                    editor.setPaper(kind)
                } label: {
                    PageTypeTile(kind: kind, selected: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(appCopy: "\(kind.title) paper"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("background.paper.\(kind.rawValue)")
            }
        }
        .frame(height: 48)
        .background(BackgroundTray())
    }
}

/// The page color snap row (P2A, D8A): Pick and Custom (they open today's
/// eyedropper and sheet), the page's latest painting once Mira painted it,
/// Default (no color), then the page colors. The page stays still while
/// the dots move; the one that settles crossfades onto it (P3A).
private struct PageColorRow: View {
    @Bindable var editor: CanvasViewModel
    let painting: Bool
    let onCustomColor: (PageColorRequest) -> Void

    /// The latest painting the page wore since the row opened: a color that
    /// replaces it leaves its cell in the row, to bring it back (final 45).
    @State private var latest: (fileName: String, describes: String)?

    init(editor: CanvasViewModel, painting: Bool, onCustomColor: @escaping (PageColorRequest) -> Void) {
        self.editor = editor
        self.painting = painting
        self.onCustomColor = onCustomColor
        let memory = editor.memory
        _latest = State(initialValue: memory.backgroundFileName.isEmpty
            ? nil : (memory.backgroundFileName, memory.backgroundSummary))
    }

    private static let pick = PageColorRequest.pick.rawValue
    private static let custom = PageColorRequest.custom.rawValue
    private static let paintedID = "painted"
    private static let defaultID = "default"

    var body: some View {
        SnapRow(
            ids: ids, selected: selected, cellWidth: 44, spacing: 2,
            identifier: { "background.color.\($0)" },
            onApply: apply,
            isAction: { $0 == Self.pick || $0 == Self.custom },
            onAction: { onCustomColor($0 == Self.pick ? .pick : .custom) },
            cell: cell
        )
        .frame(height: 48)
        .background(BackgroundTray())
        .disabled(painting)
        .opacity(painting ? 0.45 : 1)
        .onChange(of: [editor.memory.backgroundFileName, editor.memory.backgroundSummary]) { _, now in
            if !now[0].isEmpty { latest = (now[0], now[1]) }
        }
    }

    /// The Painted cell's painting: the one the page wears, else the latest
    /// one a color replaced. Read in the same render as `selected`, so the
    /// cell is never missing while the row moves to it.
    private var painted: (fileName: String, describes: String)? {
        let memory = editor.memory
        return memory.backgroundFileName.isEmpty ? latest : (memory.backgroundFileName, memory.backgroundSummary)
    }

    private var ids: [String] {
        [Self.pick, Self.custom] + (painted == nil ? [] : [Self.paintedID]) + [Self.defaultID]
            + BackgroundRowView.pageSwatches.map(\.hex)
    }

    /// What the page wears: a painting covers any color under it.
    private var selected: String {
        let color = editor.memory.pageColorName
        if !editor.memory.backgroundFileName.isEmpty { return Self.paintedID }
        if color.isEmpty { return Self.defaultID }
        return BackgroundRowView.pageSwatches.contains { $0.hex == color } ? color : Self.custom
    }

    private func apply(_ id: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch id {
            case Self.defaultID:
                editor.resetPageBackground()
            case Self.paintedID:
                if let painted { editor.setBackground(fileName: painted.fileName, describes: painted.describes) }
            default:
                editor.setPageColor(id)
            }
        }
    }

    @ViewBuilder private func cell(_ id: String) -> some View {
        let on = id == selected
        Group {
            switch id {
            case Self.pick:
                PickColorDot()
                    .accessibilityLabel(Text("Pick a page color"))
            case Self.custom:
                CustomColorDot(selected: on)
                    .accessibilityLabel(Text("Custom page color"))
            case Self.paintedID:
                PaintedColorDot(selected: on)
                    .accessibilityLabel(Text("Mira's painting"))
            case Self.defaultID:
                DefaultColorDot(selected: on)
                    .accessibilityLabel(Text("Default backdrop"))
            default:
                PageSwatch(color: Palette.color(named: id), selected: on)
                    .accessibilityLabel(Text(copy: BackgroundRowView.pageSwatches.first { $0.hex == id }?.name ?? id))
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

/// What the Custom and Pick dots ask the color sheet for.
enum PageColorRequest: String, Identifiable {
    case custom, pick
    var id: String { rawValue }
}
