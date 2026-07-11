import MiraNoteKit
import SwiftUI

/// The on-canvas sticker edit panel: one instruction, then the same
/// pipeline as make-sticker (stylize -> cutout -> outline) so the
/// die-cut look survives shape changes. Replaces in place; one undo.
struct StickerEditPanel: View {
    @Bindable var editor: CanvasViewModel
    let itemID: CanvasItem.ID
    var studio: ImageStudioService
    var onClose: () -> Void

    @State private var instruction = ""
    @State private var editing = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        ContextCard(title: "Edit sticker") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Tell AI what to change", text: $instruction)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.forest)
                        .accessibilityIdentifier("sticker.ai.instruction")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Palette.paper)
                                .overlay(Capsule().strokeBorder(
                                    Palette.hairline, lineWidth: Metrics.hairline))
                        )

                    Button {
                        runEdit()
                    } label: {
                        Text(editing ? "Working..." : "Go")
                            .font(.miraLabel)
                            .foregroundStyle(Palette.onInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Palette.ink))
                    }
                    .buttonStyle(.plain)
                    .disabled(editing || instruction.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("sticker.ai.run")

                    Button("Done") { onClose() }
                        .font(.miraLabel)
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
                        .accessibilityIdentifier("sticker.done")
                }

                if let notice {
                    Text(notice)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var currentSticker: GeneratedSticker? {
        if case .sticker(let sticker) = editor.item(itemID)?.content { return sticker }
        return nil
    }

    /// Stylize -> cutout -> outline -> replace in place; the new version
    /// joins favorites. Nothing changes unless the whole pipeline succeeds.
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
                let outlined = try await studio.outline(image: cut)
                let fileName = try imageStore.save(outlined, id: UUID())
                let edited = GeneratedSticker(
                    prompt: sticker.prompt,
                    symbolName: sticker.symbolName,
                    fileName: fileName
                )
                editor.replaceSticker(itemID: itemID, with: edited)
                favoritesStore.add(edited)
                instruction = ""
                notice = "Done -- take a look. Undo brings the old one back."
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}
