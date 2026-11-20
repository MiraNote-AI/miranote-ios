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
    /// stacked. The slot keeps the tool bar's 40; a taller row rises over
    /// the card's foot, and the card never resizes. The painting's status,
    /// or why it did not come, shows one line above the row (G25).
    var backgroundSlot: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
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
        .frame(height: 40, alignment: .bottom)
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

/// An item's row: today's curated sets, page colors and page types, one
/// row each; every tap applies to the page at once, one undo step.
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
        case .color: colorRow
        case .paper: paperRow
        }
    }

    // MARK: Sets

    /// 102 tall: rises over the card's foot.
    private var setsRow: some View {
        let worn = editor.wornCuratedSet()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CuratedSet.all) { set in
                    let look = CuratedSetLook.look(for: set)
                    Button {
                        editor.applyCuratedSet(set)
                    } label: {
                        CuratedSetCard(set: set, worn: worn == set)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(look.displayLabel) and \(look.bodyLabel)")
                    .accessibilityAddTraits(worn == set ? .isSelected : [])
                    .accessibilityIdentifier("background.set.\(set.id)")
                }
            }
        }
        .frame(height: 102)
    }

    // MARK: Color

    /// The page's own color when it shows: not while a painting covers it.
    private var pageColor: String {
        editor.memory.backgroundFileName.isEmpty ? editor.memory.pageColorName : ""
    }

    /// The five page colors, then Custom and Pick, evenly spaced. The two
    /// tools carry their names for VoiceOver; their glyphs say it on screen.
    private var colorRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.pageSwatches, id: \.hex) { swatch in
                swatchButton(swatch)
                Spacer(minLength: 4)
            }
            colorTool(request: .custom) { CustomColorDot() }
            Spacer(minLength: 4)
            colorTool(request: .pick) { PickColorDot() }
        }
        .frame(height: 40)
        .disabled(painting)
        .opacity(painting ? 0.45 : 1)
    }

    private func swatchButton(_ swatch: (hex: String, name: String)) -> some View {
        let chosen = pageColor == swatch.hex
        return Button {
            // The chosen dot, tapped again, gives the page back its default
            // backdrop; the paper stays.
            if chosen {
                editor.resetPageBackground()
            } else {
                editor.setPageColor(swatch.hex)
            }
        } label: {
            PageSwatch(color: Palette.color(named: swatch.hex), selected: chosen)
                .dotHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copy: swatch.name))
        .accessibilityHint(chosen ? Text("Returns the page to its default backdrop") : Text(verbatim: ""))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("background.color.\(swatch.hex)")
    }

    private func colorTool<Dot: View>(request: PageColorRequest, @ViewBuilder dot: () -> Dot) -> some View {
        Button {
            onCustomColor(request)
        } label: {
            dot().dotHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(request == .custom ? Text("Custom page color") : Text("Pick a page color"))
        .accessibilityIdentifier("background.color.\(request.rawValue)")
    }

    // MARK: Paper

    /// 63 tall: rises over the card's foot.
    private var paperRow: some View {
        HStack(spacing: 6) {
            ForEach(PaperKind.allCases, id: \.self) { kind in
                let selected = editor.memory.paper == kind
                Button {
                    editor.setPaper(kind)
                } label: {
                    PageTypeTile(kind: kind, selected: selected)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(appCopy: "\(kind.title) paper"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("background.paper.\(kind.rawValue)")
            }
        }
    }
}

private extension View {
    /// A 28 pt color dot taps as a 44 x 44 box without moving the row.
    func dotHitTarget() -> some View {
        padding(8)
            .contentShape(Rectangle())
            .padding(-8)
    }
}

/// What the Custom and Pick dots ask the color sheet for.
enum PageColorRequest: String, Identifiable {
    case custom, pick
    var id: String { rawValue }
}
