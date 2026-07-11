import Foundation

// The sound-content mutator (its own file for the CanvasViewModel
// size cap). Snapshots internally: one undo per call.
extension CanvasViewModel {
    public func setSoundNote(itemID: CanvasItem.ID, to note: String) {
        guard let index = index(of: itemID),
              case .sound(var clip) = memory.items[index].content else { return }
        beginChange()
        clip.note = note
        memory.items[index].content = .sound(clip)
    }
}
