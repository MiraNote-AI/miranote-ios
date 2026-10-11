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

    public func setPaper(_ paper: PaperKind) {
        guard memory.paper != paper else { return }
        beginChange()
        memory.paper = paper
    }

    /// A solid page color. Picking one removes a painted backdrop in the same
    /// undo step: the painting draws over the color, so keeping it would
    /// make the pick invisible. `recordingUndo: false` is for a color picker
    /// drag's live updates, after one recorded call.
    public func setPageColor(_ colorName: String, recordingUndo: Bool = true) {
        let clearsPainting = !colorName.isEmpty && !memory.backgroundFileName.isEmpty
        guard memory.pageColorName != colorName || clearsPainting else { return }
        if recordingUndo { beginChange() }
        memory.pageColorName = colorName
        if clearsPainting {
            memory.backgroundFileName = ""
            memory.backgroundSummary = ""
        }
    }

    /// Back to the default gradient: no page color, no painting. One undo.
    public func resetPageBackground() {
        guard !memory.pageColorName.isEmpty || !memory.backgroundFileName.isEmpty else { return }
        beginChange()
        memory.pageColorName = ""
        memory.backgroundFileName = ""
        memory.backgroundSummary = ""
    }
}
