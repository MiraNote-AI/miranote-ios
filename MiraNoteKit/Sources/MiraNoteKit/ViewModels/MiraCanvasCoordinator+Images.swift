import CoreGraphics
import Foundation

// Image and style outcome application plus the two-candidate flow
// (split from MiraCanvasCoordinator.swift for the size caps). Every
// editor mutator called here snapshots internally, so each receipt's
// Revert is exactly one undo.
extension MiraCanvasCoordinator {
    /// Apply an image/style outcome from settle().
    func settleImageOutcome(_ outcome: MiraOutcome, editor: CanvasViewModel) {
        switch outcome {
        case .imageChoices(let images, let prompt, let placement):
            phase = .imageChoices(images, prompt: prompt, placement: placement)
        case .backgroundCleared(let receipt):
            editor.setBackground(fileName: "")
            showReceipt(receipt, editor: editor)
        case .imageReplaced(let id, let data, let receipt):
            settleImageReplaced(id, data: data, receipt: receipt, editor: editor)
        case .stickerReplaced(let id, let data, let prompt, let receipt):
            settleStickerReplaced(id, data: data, prompt: prompt,
                                  receipt: receipt, editor: editor)
        case .stickerEdited(let id, let data, let receipt):
            settleStickerEdited(id, data: data, receipt: receipt, editor: editor)
        case .filterApplied(let id, let name, let receipt):
            editor.setImageFilter(itemID: id, to: name)
            showReceipt(receipt, editor: editor)
        case .frameApplied(let id, let name, let receipt):
            editor.setImageFrame(itemID: id, to: name)
            showReceipt(receipt, editor: editor)
        case .textResized(let id, let up, let receipt):
            settleTextResize(id, up: up, receipt: receipt, editor: editor)
        case .textRecolored(let id, let colorName, let receipt):
            editor.setTextColorName(itemID: id, to: colorName)
            showReceipt(receipt, editor: editor)
        default:
            return
        }
    }

    /// Land the title above the current topmost element, never on top of
    /// it: the box is sized to its words (two-line titles run taller than
    /// one), and when the headroom cannot fit it the page slides down
    /// rather than the title covering the content. addText snapshots
    /// before the moves, so the receipt's Revert is one undo. (Lives here
    /// with the other landing helpers for the coordinator's size cap.)
    func landTitle(_ title: String, receipt: MiraReceipt, editor: CanvasViewModel) {
        let boxHeight = max(60, Memory.estimatedTextHeight(title, pointSize: 30, width: 270))
        let currentTop = editor.items
            .map { $0.position.y - $0.size.height / 2 }
            .min() ?? (50 + boxHeight)
        let titleY = currentTop - 14 - boxHeight / 2
        let overflow = max(0, 36 - (titleY - boxHeight / 2))
        let existing = editor.items.map { ($0.id, $0.position) }
        editor.addText(
            title,
            at: CGPoint(x: 150, y: titleY + overflow),
            pointSize: 30,
            size: CGSize(width: 270, height: boxHeight)
        )
        for (id, position) in existing where overflow > 0 {
            editor.move(itemID: id, to: CGPoint(x: position.x, y: position.y + overflow))
        }
        showReceipt(receipt, editor: editor)
    }

    /// Tap on candidate `index`: write the file, land it, receipt.
    public func placeImageChoice(_ index: Int, editor: CanvasViewModel) {
        guard case .imageChoices(let images, let prompt, let placement) = phase,
              images.indices.contains(index),
              let fileName = try? imageStore.save(images[index], id: UUID())
        else { return }
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 90, 4000))
        switch placement {
        case .sticker:
            let generated = GeneratedSticker(
                prompt: prompt, symbolName: "sparkles", fileName: fileName)
            editor.addSticker(generated, at: position)
            stickerFavorites.add(generated)
            showReceipt(MiraReceipt(
                changed: "Added a sticker.",
                kept: "Everything else is untouched."), editor: editor)
        case .picture:
            editor.addImages(
                [ImageRef(displayName: prompt, fileName: fileName)],
                around: position)
            showReceipt(MiraReceipt(
                changed: "Added a picture.",
                kept: "Everything else is untouched."), editor: editor)
        case .background:
            editor.setBackground(fileName: fileName)
            showReceipt(MiraReceipt(
                changed: "Set the page background.",
                kept: "Everything else is untouched."), editor: editor)
        }
    }

    /// The xmark: both candidates evaporate, canvas untouched.
    public func discardImageChoices() {
        guard case .imageChoices = phase else { return }
        phase = .idle
    }

    private func settleImageReplaced(_ id: CanvasItem.ID, data: Data,
                                     receipt: MiraReceipt, editor: CanvasViewModel) {
        guard editor.item(id) != nil,
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The photo I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        editor.replaceImageFile(itemID: id, fileName: fileName)
        showReceipt(receipt, editor: editor)
    }

    private func settleStickerReplaced(_ id: CanvasItem.ID, data: Data, prompt: String,
                                       receipt: MiraReceipt, editor: CanvasViewModel) {
        guard editor.item(id) != nil,
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The photo I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        let sticker = GeneratedSticker(prompt: prompt, symbolName: "sparkles",
                                       fileName: fileName)
        editor.replaceImageWithSticker(itemID: id, sticker: sticker)
        stickerFavorites.add(sticker)
        showReceipt(receipt, editor: editor)
    }

    /// The target must STILL be a sticker (an undo mid-flight can revert
    /// a cut photo): never convert an image through this path. Label and
    /// symbol carry over from the sticker being edited.
    private func settleStickerEdited(_ id: CanvasItem.ID, data: Data,
                                     receipt: MiraReceipt, editor: CanvasViewModel) {
        guard case .sticker(let old)? = editor.item(id)?.content,
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The sticker I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        let edited = GeneratedSticker(prompt: old.prompt, symbolName: old.symbolName,
                                      fileName: fileName)
        editor.replaceSticker(itemID: id, with: edited)
        stickerFavorites.add(edited)
        showReceipt(receipt, editor: editor)
    }

    private func settleTextResize(_ id: CanvasItem.ID, up: Bool,
                                  receipt: MiraReceipt, editor: CanvasViewModel) {
        guard case .text(let block) = editor.item(id)?.content else { return }
        let steps: [CGFloat] = [13, 17, 30]
        let nearest = steps.min {
            abs($0 - block.pointSize) < abs($1 - block.pointSize)
        } ?? 17
        let index = steps.firstIndex(of: nearest) ?? 1
        let next = steps[max(0, min(steps.count - 1, index + (up ? 1 : -1)))]
        editor.setTextPointSize(itemID: id, to: next)
        editor.autosizeTextHeight(itemID: id, to: Memory.estimatedTextHeight(
            block.text, pointSize: next,
            width: editor.item(id)?.size.width ?? 220
        ))
        showReceipt(receipt, editor: editor)
    }
}
