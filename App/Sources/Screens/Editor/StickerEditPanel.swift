import MiraNoteKit
import SwiftUI

/// The on-canvas sticker edit panel: one instruction, then stylize -> cutout.
///
/// No outline pass, unlike make-sticker. A sticker already carries its white
/// die-cut edge -- the image model drew it, and /stylize now asks for it to be
/// kept -- so stroking another one around the result only thickens the edge,
/// and does it again on every edit. make-sticker still outlines because a photo
/// cut out of its background has no edge of its own.
///
/// Replaces in place; one undo.
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

    private let imageStore = ImageFileStore()

    /// The shared tool chrome (owner, 2026-10-19: one edge, one height for
    /// every tool): a line for the notice, the tool bar with Sticker lit,
    /// and the composer taking the words. The header's Canvas closes it.
    var body: some View {
        if let notice {
            Text(notice)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.chromeInset)
        }
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
            notice = "This sticker has no stored pixels to change."
            return
        }
        editing = true
        notice = nil
        Task {
            defer { editing = false }
            do {
                let styled = try await studio.stylize(image: data, instruction: words)
                let cut = try await studio.cutout(image: styled, target: nil)
                // The trim is the half of the dropped outline pass that was
                // worth keeping: /border cropped to alpha on either side of
                // the stroke. Without it the matte's transparent margin is
                // drawn as part of the picture inside an unchanged frame.
                // Measured on a real generated sticker: 0.71x a pass,
                // compounding, because what is saved here is the input to the
                // next edit. See StickerTrim for the numbers; same in
                // MiraIntent+Image.
                let fileName = try imageStore.save(
                    StickerTrim.croppedToOpaqueBounds(cut), id: UUID())
                let edited = GeneratedSticker(
                    prompt: sticker.prompt,
                    symbolName: sticker.symbolName,
                    fileName: fileName
                )
                editor.replaceSticker(itemID: itemID, with: edited)
                // The new sticker on the page is the receipt; Undo brings
                // the old one back.
                onClose()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}
