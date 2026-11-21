import MiraNoteKit
import SwiftUI

// MARK: - Text slot

extension CanvasScene {
    /// The text slot's one row (REQ 11-18 overlay rule): Back and the text
    /// row, or the open tool's row with its own Back. 36 tall whichever row
    /// shows, so the page under it never moves with a level change.
    var textSlot: some View {
        ZStack {
            HStack(spacing: 8) {
                if let tool = textRow {
                    TextBackKey(identifier: "text.row.back", onBack: backToTextRow)
                    toolRow(tool)
                } else {
                    TextBackKey(onBack: endTextEditing)
                    TextToolBar(alignment: editingBlock?.alignment ?? .leading, onSelect: selectTextTool)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("text.row.\(textRow.map { "\($0)" } ?? "tools")")
            .id(textRow)
            .transition(slotLevelTransition)
        }
        .frame(height: 36)
        .padding(.horizontal, Metrics.chromeInset)
        // A tap between two keys stays in the writing, off the page.
        .contentShape(Rectangle())
    }

    /// A level change in the tool slot (D7A, G26), Text and Background
    /// alike: the new row fades in rising from 6 below (deeper) or settling
    /// from 6 above (back). Opacity under Reduce Motion.
    var slotLevelTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(y: slotDeeper ? 6 : -6).combined(with: .opacity), removal: .opacity)
    }

    /// `tool`'s row in the slot, or the text row for nil.
    private func showTextRow(_ tool: TextTool?) {
        slotDeeper = tool != nil
        withAnimation(.easeOut(duration: 0.22)) { textRow = tool }
    }

    /// A tool row's Back: up to the text row. Leaving Polish keeps the
    /// version on the page (D9A).
    func backToTextRow() {
        if textRow == .ai { finishRewrite() }
        showTextRow(nil)
    }

    @ViewBuilder private func toolRow(_ tool: TextTool) -> some View {
        let block = editingBlock
        switch tool {
        case .font:
            FontChipRow(fontName: block?.fontName ?? "") { name in
                restyle { editor.setTextFont(itemID: $0, to: name) }
            }
        case .size:
            TextSizeRow(pointSize: block?.pointSize ?? TextFace.newBlockSize) { choice in
                restyle { editor.setTextPointSize(itemID: $0, to: choice.pointSize) }
            }
        case .color:
            let current = block?.colorName ?? ""
            ColorSwatchRow(
                current: current,
                isCustom: current.hasPrefix("#") && current != TextFace.newBlockColor
                    && !Palette.textSwatches.contains { $0.hex == current },
                onSwatch: { hex in
                    if let id = editor.editingTextItemID { editor.setTextColorName(itemID: id, to: hex) }
                },
                onCustom: { openColorSheet(.text) }
            )
        case .ai:
            RewriteRow(
                selected: rewrite.map(\.session.selected) ?? .original,
                pending: rewrite?.session.pending,
                enabled: rewriteAsk == nil
                    && !(block?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                onSelect: pickRewrite
            )
        case .background:
            let current = block?.backgroundColorName ?? ""
            TextBackgroundRow(
                current: current,
                isCustom: !current.isEmpty && !Palette.textBackgroundSwatches.contains { $0.hex == current },
                onPick: { hex in
                    if let id = editor.editingTextItemID { editor.setTextBackground(itemID: id, to: hex) }
                },
                onCustom: { openColorSheet(.background) }
            )
        case .align:
            EmptyView()
        }
    }

    /// A tap in the text row. Align has no row: each tap steps the
    /// alignment (screens 16-17). Every other tool's row replaces the text
    /// row (K1B).
    func selectTextTool(_ tool: TextTool) {
        switch tool {
        case .align:
            if let id = editor.editingTextItemID, let block = editingBlock {
                editor.setTextAlignment(itemID: id, to: block.alignment.next)
            }
            return
        case .ai:
            if textRow != .ai { startRewrite() }
        case .font, .size, .color, .background:
            break
        }
        showTextRow(tool)
    }

    /// A face or size change, then the block re-measured to fit the type.
    private func restyle(_ change: (CanvasItem.ID) -> Void) {
        guard let id = editor.editingTextItemID else { return }
        change(id)
        remeasureEditedText(id)
    }
}

/// A row coming into the tool slot across a swap of the dock's whole bottom
/// cluster (the tool bar and Background's row, each with its own
/// composer): it waits hidden for a moment, then fades in rising from 6
/// below (deeper) or settling from 6 above (back), as `slotLevelTransition`
/// does. A transition would keep the outgoing row and composer in the
/// layout while it plays -- two rows stacked and the card squeezed.
struct SlotEntrance: ViewModifier {
    let deeper: Bool
    let waiting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(waiting ? 0 : 1)
            .offset(y: waiting && !reduceMotion ? (deeper ? 6 : -6) : 0)
    }
}
