import Foundation

// MARK: - Idle suggestions

extension MiraCanvasCoordinator {
    /// Context-aware idle suggestions -- PAGE-level only (Meng,
    /// 2026-07-09): polishing belongs to the text editor's keyboard row,
    /// where the target block is unambiguous. Every chip must be ABOUT
    /// something already on the page, and a title is a suggestion about
    /// words, so it waits for words.
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
        return chips
    }
}
