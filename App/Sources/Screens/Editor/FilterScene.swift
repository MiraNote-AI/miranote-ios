import SwiftUI

/// Flow 7 Scene 07: filter preview -- a warm-tinted page and the Change filter
/// context card (Original / Warm / Soft / Film).
struct FilterScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Preview",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Warm film preview",
                imageTint: Palette.tan
            )
        } bottom: {
            ContextCard(title: "Change filter") {
                HStack(spacing: 10) {
                    Chip(text: "Original")
                    Chip(text: "Warm", selected: true, fillWhenSelected: false)
                    Chip(text: "Soft")
                    Chip(text: "Film")
                    Spacer()
                }
            }
            InputModeBar(active: .image, onSelect: actions.selectMode)
            ActionRow(hint: "Apply selected filter", onGo: actions.go)
        }
    }
}
