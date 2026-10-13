import Foundation

// MARK: - Idle suggestions

extension MiraCanvasCoordinator {
    /// The handoff's "Change background" quick action (screen 06), as words
    /// Mira routes to a background turn.
    public static let changeBackgroundChip = "Change the background"

    /// Re-lays the page out; also the Background tool's one-tap layout.
    public static let tidyChip = "Tidy the layout"

    /// Context-aware idle suggestions -- PAGE-level only (Meng,
    /// 2026-07-09): polishing belongs to the text editor's keyboard row,
    /// where the target block is unambiguous. Every chip must be ABOUT
    /// something already on the page, and a title is a suggestion about
    /// words, so it waits for words. A background is about what is on the
    /// page too, so it waits for something visible, and leaves once the page
    /// has its own color or painting.
    ///
    /// The handoff's quick actions (screen 06, #89 C2) map here: re-layout is
    /// "Tidy the layout", the soft title and background are their own chips.
    /// Its "Make text warmer" is deliberately not offered -- rewording is the
    /// text editor's job, per the rule above.
    ///
    /// The row is a two-slot design, so at most two chips show, by priority.
    public func suggestions(for editor: CanvasViewModel) -> [String] {
        Array(candidateSuggestions(for: editor).prefix(2))
    }

    /// What a tapped chip sends to Mira. The background chip's label is
    /// generic; the ask names what the page is about, so the painting suits
    /// the page and the stored backdrop summary describes it.
    public func ask(forSuggestion chip: String, editor: CanvasViewModel) -> String {
        guard chip == Self.changeBackgroundChip else { return chip }
        guard let subject = Self.pageSubject(editor) else {
            return "Paint a soft background that suits this page"
        }
        return "Paint a soft background for a page about \(subject)"
    }

    /// Runs a tapped chip. The background chip's ask quotes the page's own
    /// words, which may hold router keywords ("photo dump"), so it states its
    /// intent instead of having the words re-read.
    public func askSuggestion(_ chip: String, editor: CanvasViewModel) {
        let words = ask(forSuggestion: chip, editor: editor)
        let intent: MiraIntent? = chip == Self.changeBackgroundChip ? .setBackground(prompt: words) : nil
        ask(words, editor: editor, as: intent)
    }

    /// The page's most prominent words: the largest text, topmost on a tie,
    /// first line only, kept short.
    private static func pageSubject(_ editor: CanvasViewModel) -> String? {
        let blocks: [(TextBlock, CGFloat)] = editor.items.compactMap {
            guard case .text(let block) = $0.content,
                  !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (block, $0.position.y)
        }
        guard let top = blocks.min(by: { lhs, rhs in
            lhs.0.pointSize != rhs.0.pointSize ? lhs.0.pointSize > rhs.0.pointSize : lhs.1 < rhs.1
        }) else { return nil }
        let line = top.0.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? top.0.text
        return String(line.trimmingCharacters(in: .whitespaces).prefix(60))
    }

    private func candidateSuggestions(for editor: CanvasViewModel) -> [String] {
        var chips: [String] = []
        let hasText = editor.items.contains {
            if case .text = $0.content { return true } else { return false }
        }
        if editor.items.count > 1 {
            chips.append(Self.tidyChip)
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
