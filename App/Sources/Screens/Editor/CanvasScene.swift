import SwiftUI

/// Flow 7 Scene 02: the base editor -- page plus the instrument panel, with a
/// plain hint row and no context card.
struct CanvasScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Canvas",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "June 21 \u{00B7} calm afternoon"
            )
        } bottom: {
            InputModeBar(active: nil, onSelect: actions.selectMode)
            ActionRow(hint: "Choose voice, text, image, or sticker", onGo: actions.go)
        }
    }
}
