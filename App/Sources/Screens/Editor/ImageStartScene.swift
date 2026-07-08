import SwiftUI

/// The image entry point (v2.1): an "Add an image" context card offering the
/// photo library, the camera, or AI generation (which is also where sticker
/// creation now lives).
struct ImageStartScene: View {
    var actions = EditorActions()
    var onGenerate: () -> Void = {}

    var body: some View {
        EditorScaffold(
            title: "Add an image",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "June 21 \u{00B7} calm afternoon"
            )
        } bottom: {
            ContextCard(
                title: "Add an image",
                subtitle: "Pick from your library, take a photo, or generate one."
            ) {
                HStack(spacing: 10) {
                    sourceButton("Library", id: "image.library", action: actions.go)
                    sourceButton("Camera", id: "image.camera", action: actions.go)
                    sourceButton("Generate", id: "image.generate", action: onGenerate)
                    Spacer()
                }
            }
            InputModeBar(active: .image, onSelect: actions.selectMode)
            ActionRow(hint: "Open Photo Library", onGo: actions.go)
        }
    }

    private func sourceButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.miraLabel)
                .foregroundStyle(Palette.onInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Palette.ink))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
