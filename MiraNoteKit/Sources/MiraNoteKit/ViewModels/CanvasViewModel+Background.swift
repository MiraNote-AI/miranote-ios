import Foundation

// The page-background mutator (its own file for the CanvasViewModel
// size cap). Snapshots internally: one undo per call.
extension CanvasViewModel {
    /// Sets (or, with "", clears) the page's full-bleed background.
    /// A no-change call burns no undo snapshot (clearing an already
    /// default page still receipts, but undo stays honest).
    public func setBackground(fileName: String) {
        guard memory.backgroundFileName != fileName else { return }
        beginChange()
        memory.backgroundFileName = fileName
    }
}
