import Foundation

// MARK: - Idle suggestions

extension MiraCanvasCoordinator {
    /// The handoff's "Change background" quick action (screen 06), as words
    /// Mira routes to a background turn.
    public static let changeBackgroundChip = "Change the background"

    /// Context-aware idle suggestions -- PAGE-level only (Meng,
    /// 2026-07-09): polishing belongs to the text editor's keyboard row,
    /// where the target block is unambiguous. Every chip must be ABOUT
    /// something already on the page, and a title is a suggestion about
    /// words, so it waits for words. A background is about what is on the
    /// page too, so it waits for something visible, and leaves once the page
    /// has its own color or painting.
    public func suggestions(for editor: CanvasViewModel) -> [String] {
        var chips: [String] = []
        let hasText = editor.items.contains {
            if case .text = $0.content { return true } else { return false }
        }
        if editor.items.count > 1 {
            chips.append("Tidy the layout")
        }
        let hasTitle = editor.items.contains {
            if case .text(let block) = $0.content { return block.pointSize >= 24 }
            return false
        }
        if hasText, !hasTitle {
            chips.append("Add a soft title")
        }
        let hasVisibleContent = editor.items.contains {
            if case .sound = $0.content { return false } else { return true }
        }
        let onDefaultBackdrop = editor.memory.backgroundFileName.isEmpty
            && editor.memory.pageColorName.isEmpty
        if hasVisibleContent, onDefaultBackdrop {
            chips.append(Self.changeBackgroundChip)
        }
        return chips
    }
}
