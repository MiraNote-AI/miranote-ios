import Foundation

/// One-tap layouts (#183): templates are tried on the page as previews, and
/// the one kept is a single undo step back to the page before any of them.
extension CanvasViewModel {
    /// Shows `items` on the page without an undo step (a template being tried).
    public func previewLayout(_ items: [CanvasItem]) {
        if layoutPreviewOrigin == nil { layoutPreviewOrigin = memory.items }
        memory.items = keepingSentences(items)
    }

    /// Cancel: the page as it was before any template was tried.
    public func cancelLayout(to original: [CanvasItem]) {
        memory.items = keepingSentences(original)
        layoutPreviewOrigin = nil
    }

    /// Keeps the layout on the page now; undo goes back to `original`.
    public func commitLayout(from original: [CanvasItem]) {
        let original = keepingSentences(original)
        layoutPreviewOrigin = nil
        let laid = memory.items
        guard laid != original else { return }
        memory.items = original
        beginChange()
        memory.items = laid
    }

    /// A photo's sentence that lands while templates are tried (vision is
    /// slower than a tap on Layout) is the page's own work, not an edit: the
    /// page as it was keeps it too, so no card, Cancel or Done drops it.
    func keepSentenceWhileTrying(itemID: CanvasItem.ID, summary: String) {
        guard let index = layoutPreviewOrigin?.firstIndex(where: { $0.id == itemID }),
              case .image(var ref) = layoutPreviewOrigin?[index].content else { return }
        ref.summary = summary
        layoutPreviewOrigin?[index].content = .image(ref)
    }

    /// `items` (a template, or the page put back) with each photo's sentence
    /// as the page has it now.
    private func keepingSentences(_ items: [CanvasItem]) -> [CanvasItem] {
        var sentences: [CanvasItem.ID: String] = [:]
        for item in layoutPreviewOrigin ?? memory.items {
            if case .image(let ref) = item.content { sentences[item.id] = ref.summary }
        }
        return items.map { item in
            guard case .image(var ref) = item.content, let sentence = sentences[item.id],
                  ref.summary != sentence else { return item }
            ref.summary = sentence
            var kept = item
            kept.content = .image(ref)
            return kept
        }
    }
}
