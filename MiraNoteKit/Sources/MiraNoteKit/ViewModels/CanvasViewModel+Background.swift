import Foundation

// The page-background mutator (its own file for the CanvasViewModel
// size cap). Snapshots internally: one undo per call.
extension CanvasViewModel {
    /// Sets (or, with "", clears) the page's full-bleed background.
    public func setBackground(fileName: String) {
        beginChange()
        memory.backgroundFileName = fileName
    }
}
