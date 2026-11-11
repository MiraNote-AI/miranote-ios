import Foundation

/// One-tap layouts (#183): templates are tried on the page as previews, and
/// the one kept is a single undo step back to the page before any of them.
extension CanvasViewModel {
    /// Shows `items` on the page without an undo step (a template being tried).
    public func previewLayout(_ items: [CanvasItem]) {
        if layoutPreviewOrigin == nil { layoutPreviewOrigin = memory.items }
        memory.items = items
    }

    /// Cancel: the page as it was before any template was tried.
    public func cancelLayout(to original: [CanvasItem]) {
        memory.items = original
        layoutPreviewOrigin = nil
    }

    /// Keeps the layout on the page now; undo goes back to `original`.
    public func commitLayout(from original: [CanvasItem]) {
        layoutPreviewOrigin = nil
        let laid = memory.items
        guard laid != original else { return }
        memory.items = original
        beginChange()
        memory.items = laid
    }
}
