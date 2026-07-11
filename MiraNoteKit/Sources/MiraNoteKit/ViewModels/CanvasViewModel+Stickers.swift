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
    public func replaceSticker(itemID: CanvasItem.ID, with sticker: GeneratedSticker) {
        guard let index = index(of: itemID),
              case .sticker = memory.items[index].content else { return }
        beginChange()
        memory.items[index].content = .sticker(sticker)
    }
}
