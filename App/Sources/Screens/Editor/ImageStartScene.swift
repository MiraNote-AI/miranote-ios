import SwiftUI

/// Flow 7 Scene 05: the image entry point -- a "Choose photos" context card
/// offering the photo library or the camera.
struct ImageStartScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Add images",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "June 21 \u{00B7} calm afternoon"
            )
        } bottom: {
            ContextCard(
                title: "Choose photos",
                subtitle: "Start from camera roll, camera, imported media, or a link."
            ) {
                HStack(spacing: 10) {
                    sourceButton("Photo Library")
                    sourceButton("Camera")
                    Spacer()
                }
            }
            InputModeBar(active: .image, onSelect: actions.selectMode)
            ActionRow(hint: "Open Photo Library", onGo: actions.go)
        }
    }

    private func sourceButton(_ title: String) -> some View {
        Text(title)
            .font(.miraLabel)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.ink))
    }
}
