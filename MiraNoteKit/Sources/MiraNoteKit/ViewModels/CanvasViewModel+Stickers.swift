import Foundation

// Sticker-content mutators (split from CanvasViewModel.swift for the
// file-length cap). Both snapshot internally: one undo per call.
extension CanvasViewModel {
    /// The make-sticker path: a photo's pixels become a die-cut sticker.
    public func replaceImageWithSticker(itemID: CanvasItem.ID, sticker: GeneratedSticker) {
        guard let index = index(of: itemID),
              case .image = memory.items[index].content else { return }
        beginChange()
        memory.items[index].content = .sticker(sticker)
    }

    /// The edit-sticker path: new pixels for an existing sticker, in place.
    /// With `regrowth` (Outline) the frame grows round the art by the edge,
    /// so the art keeps its size and place; the same step undoes both.
    public func replaceSticker(itemID: CanvasItem.ID, with sticker: GeneratedSticker,
                               regrowth: StickerTrim.Regrowth? = nil) {
        guard let index = index(of: itemID),
              case .sticker = memory.items[index].content else { return }
        beginChange()
        memory.items[index].content = .sticker(sticker)
        guard let regrowth else { return }
        // The shift is in the frame's axes; the frame turns with the item
        // (SwiftUI's rotationEffect: clockwise on screen, y down).
        let turn = memory.items[index].rotation * .pi / 180
        let shift = regrowth.centerShift
        memory.items[index].size = regrowth.size
        memory.items[index].position.x += shift.dx * cos(turn) - shift.dy * sin(turn)
        memory.items[index].position.y += shift.dx * sin(turn) + shift.dy * cos(turn)
    }
}
