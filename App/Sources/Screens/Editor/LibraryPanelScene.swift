import MiraNoteKit
import SwiftUI

/// The Library panel (fourth toolbar slot, issue #30): the shared folder
/// of saved stickers and images. One tap places an item on the page --
/// stickers land as stickers, photos as photos.
struct LibraryPanelScene: View {
    @Bindable var editor: CanvasViewModel
    var actions = EditorActions()

    @State private var entries: [GeneratedSticker] = []

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        EditorScaffold(
            title: "Your library",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            // The user's own page up top, same as the Image panel: what
            // the picked item will land on.
            ScrollView(showsIndicators: false) {
                StaticPageView(memory: editor.memory, showsSound: false)
                    .padding(.horizontal, Metrics.screenPadding)
            }
        } bottom: {
            panel
            InputModeBar(active: .library, onSelect: actions.selectMode)
        }
        .onAppear {
            // Hygiene: drop entries whose image no longer decodes. The
            // stricter mock-debris size sweep stays with the Image panel
            // (its minSide would also eat legitimately tiny artwork here).
            entries = favoritesStore.pruned(imageSide: { name in
                guard let image = CanvasImageCache.image(
                    fileName: name, filterName: "", store: imageStore
                ) else { return nil }
                return min(image.size.width, image.size.height)
            }, minSide: 1)
        }
    }

    private var panel: some View {
        ContextCard(
            title: "Your library",
            subtitle: "Saved stickers and photos, one tap from the page."
        ) {
            if entries.isEmpty {
                Text("Nothing here yet -- stickers you make and photos you save land in this folder.")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("library.empty")
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(entries) { entry in
                        Button {
                            place(entry)
                        } label: {
                            thumb(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library.item.\(entry.id.uuidString)")
                    }
                }
            }
        }
    }

    /// Stickers keep sticker behavior (transparent, scalable); images
    /// arrive like an imported photo.
    private func place(_ entry: GeneratedSticker) {
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 80, 4000))
        switch entry.kind {
        case .sticker:
            editor.addSticker(entry, at: position)
        case .image:
            editor.addImages(
                [ImageRef(displayName: entry.prompt, fileName: entry.fileName)],
                around: position
            )
        }
        actions.leading()
    }

    @ViewBuilder private func thumb(_ entry: GeneratedSticker) -> some View {
        if let image = CanvasImageCache.image(
            fileName: entry.fileName, filterName: "", store: imageStore
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
        } else {
            Image(systemName: entry.symbolName)
                .frame(width: 64, height: 64)
                .foregroundStyle(Palette.taupe)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
        }
    }
}
