import Foundation

// The page-background mutator (its own file for the CanvasViewModel
// size cap). Snapshots internally: one undo per call.
extension CanvasViewModel {
    /// Sets (or, with "", clears) the page's full-bleed background.
    /// A no-change call burns no undo snapshot (clearing an already
    /// default page still receipts, but undo stays honest).
    /// `describes` is what the backdrop shows -- the prompt it came
    /// from. Stored beside the file so the page map can tell Mira what
    /// is behind the words without spending a look at the picture.
    public func setBackground(fileName: String, describes: String = "") {
        guard memory.backgroundFileName != fileName else { return }
        beginChange()
        memory.backgroundFileName = fileName
        memory.backgroundSummary = fileName.isEmpty ? "" : describes
    }
}
