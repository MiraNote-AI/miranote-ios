import MiraNoteKit
import SwiftUI

/// The on-canvas sticker edit panel: two tiles, as on Photo Editing but only
/// these two (team decision 2026-10-28) -- AI Editing, the instruction below
/// (stylize -> cutout), and Outline, a white edge drawn round the sticker.
///
/// Stickers come out with no edge (2026-10-24), so the edge is the user's to
/// add. AI Editing adds none of its own: one the instruction asks for, or one
/// already there, is the model's to keep. Outline on a sticker that already
/// has an edge draws a second one round it.
///
/// Either replaces the sticker in place; one undo.
struct StickerEditPanel: View {
    @Bindable var editor: CanvasViewModel
    let itemID: CanvasItem.ID
    var studio: ImageStudioService
    /// The instruction's keyboard; a tap on the page lowers it.
    var focus: FocusState<Bool>.Binding
    var onClose: () -> Void
    /// The tool bar's taps, as on every other tool.
    var onSelectTool: (EditorMode) -> Void = { _ in }

    @State private var instruction = ""
    @State private var editing = false
    @State private var notice: String?
    /// Set when the panel goes away: a result that lands after that must not
    /// swap the sticker or close a panel that is no longer there.
    @State private var cancelled = false

    private let imageStore = ImageFileStore()

    /// The shared tool chrome (owner, 2026-10-19: one edge, one height for
    /// every tool): a line for the notice, the two tiles, the tool bar with
    /// Sticker lit, and the composer taking AI Editing's words. The header's
    /// Canvas closes it.
    var body: some View {
        if let notice {
            Text(notice)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.chromeInset)
        }
        HStack(spacing: 14) {
            // The composer below is AI Editing's, so its tile stays lit;
            // a tap puts the cursor there.
            EditTile(label: "AI Editing", selected: true) { focus.wrappedValue = true }
                .accessibilityIdentifier("sticker.tile.ai")
            EditTile(label: "Outline", selected: false, action: runOutline)
                .accessibilityIdentifier("sticker.tile.outline")
            Spacer(minLength: 0)
        }
        .disabled(editing)
        .padding(.horizontal, Metrics.chromeInset)
        InputModeBar(active: .sticker, onSelect: onSelectTool)
        ToolComposer(
            placeholder: "Tell Mira what to change",
            text: $instruction,
            action: editing ? "Working..." : "Go",
            actionEnabled: !editing && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fieldID: "sticker.ai.instruction",
            actionID: "sticker.ai.run",
            focus: focus,
            onAction: runEdit
        )
        .onAppear { cancelled = false }
        .onDisappear { cancelled = true }
    }

    private var currentSticker: GeneratedSticker? {
        if case .sticker(let sticker) = editor.item(itemID)?.content { return sticker }
        return nil
    }

    /// Stylize -> cutout -> trim -> replace in place. Nothing changes unless
    /// the whole pipeline succeeds.
    private func runEdit() {
        let words = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editing, !words.isEmpty, let sticker = currentSticker,
              let data = imageStore.data(forFileName: sticker.fileName) else {
            notice = String(appCopy: "This sticker has no stored pixels to change.")
            return
        }
        replace(sticker) {
            let styled = try await studio.stylize(image: data, instruction: words)
            let cut = try await studio.cutout(image: styled, target: nil)
            // The trim is the half of the old outline pass that was worth
            // keeping: /border cropped to alpha on either side of the
            // stroke. Without it the matte's transparent margin is drawn as
            // part of the picture inside an unchanged frame. Measured on a
            // real generated sticker: 0.71x a pass, compounding, because
            // what is saved here is the input to the next edit. See
            // StickerTrim for the numbers; same in MiraIntent+Image.
            return StickerTrim.croppedToOpaqueBounds(cut)
        }
    }

    /// A white edge round the sticker as it is now, in place. Drawn on the
    /// phone and already cropped to the sticker and its edge; the frame grows
    /// by the edge, so the art keeps its size and place.
    private func runOutline() {
        guard !editing else { return }
        guard let sticker = currentSticker,
              let data = imageStore.data(forFileName: sticker.fileName) else {
            notice = String(appCopy: "This sticker has no stored pixels to outline.")
            return
        }
        replace(sticker, growingFrom: data) { try await studio.outline(image: data) }
    }

    /// `growingFrom`: the sticker's pixels before, when the new ones are them
    /// with an edge round them (Outline).
    private func replace(_ sticker: GeneratedSticker, growingFrom old: Data? = nil,
                         with make: @escaping () async throws -> Data) {
        editing = true
        notice = nil
        Task {
            defer { editing = false }
            do {
                let made = try await make()
                guard !cancelled else { return }
                let fileName = try imageStore.save(made, id: UUID())
                let edited = GeneratedSticker(
                    prompt: sticker.prompt,
                    symbolName: sticker.symbolName,
                    fileName: fileName
                )
                let frame = editor.item(itemID)?.size
                let regrowth = old.flatMap { old in
                    frame.flatMap { StickerTrim.regrowth(from: old, to: made, in: $0) }
                }
                editor.replaceSticker(itemID: itemID, with: edited, regrowth: regrowth)
                // The new sticker on the page is the receipt; Undo brings
                // the old one back.
                onClose()
            } catch {
                guard !cancelled else { return }
                notice = (error as? LocalizedError)?.errorDescription
                    ?? String(appCopy: "That didn't work this time. Try again?")
            }
        }
    }
}
