import SwiftUI

/// Flow 7 Scene 08: AI sticker creation -- a placed cup sticker plus the
/// prompt + Generate context card.
struct AIStickerScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Create sticker",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Add a small visual feeling"
            ) {
                PlacedSticker()
            }
        } bottom: {
            ContextCard(title: "AI sticker") {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        promptField
                        generateButton
                    }
                    HStack(spacing: 8) {
                        Chip(text: "cup", selected: true, fillWhenSelected: false)
                        Chip(text: "bloom")
                        Chip(text: "soft")
                        Chip(text: "note")
                        Spacer()
                    }
                }
            }
            InputModeBar(active: .sticker, onSelect: actions.selectMode)
            ActionRow(hint: "Generate sticker from keyword", onGo: actions.go)
        }
    }

    private var promptField: some View {
        HStack {
            Text("sleepy cafe cat")
                .font(.miraBody)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Palette.paper)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
    }

    private var generateButton: some View {
        Text("Generate")
            .font(.miraLabel)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.ink))
    }
}

/// Flow 7 Scene 09: the sticker library -- category tabs and a row of stickers.
struct StickerLibraryScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Sticker Library",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Selected sticker placed"
            ) {
                PlacedSticker()
            }
        } bottom: {
            ContextCard(title: "Stickers") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Chip(text: "Favorites", selected: true, compact: true)
                        Chip(text: "AI Made", compact: true)
                        Chip(text: "Cutouts", compact: true)
                        Chip(text: "Trending", compact: true)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        stickerItem("cup")
                        stickerItem("bloom")
                        stickerItem("soft")
                        stickerItem("note")
                        Spacer()
                    }
                }
            }
            InputModeBar(active: .sticker, onSelect: actions.selectMode)
            ActionRow(hint: "Add selected sticker", onGo: actions.go)
        }
    }

    private func stickerItem(_ label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                .frame(width: 50, height: 50)
                .overlay(Image(systemName: "seal").foregroundStyle(Palette.taupe))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
