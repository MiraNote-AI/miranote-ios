import Foundation

// Text-block style mutators (redesign phase B1). Each records one undo step,
// and a call that changes nothing records none.
extension CanvasViewModel {
    public func setTextFont(itemID: CanvasItem.ID, to fontName: String) {
        updateTextStyle(itemID) { $0.fontName = fontName }
    }

    public func setTextAlignment(itemID: CanvasItem.ID, to alignment: TextAlign) {
        updateTextStyle(itemID) { $0.alignment = alignment }
    }

    /// "" removes the text background. `recordingUndo` works as on
    /// `setTextColorName`: false for a color picker drag's live updates.
    public func setTextBackground(itemID: CanvasItem.ID, to colorName: String, recordingUndo: Bool = true) {
        updateTextStyle(itemID, recordingUndo: recordingUndo) { $0.backgroundColorName = colorName }
    }

    /// Blocks this large or larger are display type (titles); the app's
    /// default face draws them in the serif.
    /// Nonisolated: a constant, read from view code outside the main actor
    /// (TextFace measures text from any context).
    public nonisolated static let displayPointSize: CGFloat = 24

    private func updateTextStyle(
        _ itemID: CanvasItem.ID, recordingUndo: Bool = true, _ change: (inout TextBlock) -> Void
    ) {
        guard let index = memory.items.firstIndex(where: { $0.id == itemID }),
              case .text(let block) = memory.items[index].content else { return }
        var styled = block
        change(&styled)
        guard styled != block else { return }
        if recordingUndo { beginChange() }
        memory.items[index].content = .text(styled)
    }
}
