import SwiftUI

/// The base editor (v2.1): page plus the three-mode instrument panel and the
/// unified Mira bar. Header is back / undo / Done -- no title, no sub-toolbar.
struct CanvasScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            leading: "Home",
            leadingSymbol: "chevron.left",
            onLeading: actions.leading,
            onTrailing: actions.done,
            onUndo: undoPlaceholder
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "June 21 \u{00B7} calm afternoon"
            )
        } bottom: {
            InputModeBar(active: nil, onSelect: actions.selectMode)
            ActionRow(hint: "Ask Mira anything", onGo: actions.go)
        }
    }

    /// No-op until the Phase B canvas element model brings a real undo stack.
    private func undoPlaceholder() {}
}
