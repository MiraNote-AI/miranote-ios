import MiraNoteKit
import SwiftUI

/// The Library panel: the fourth instrument-bar mode, a shelf of saved
/// material grouped by category. One group exists for now -- Favorites
/// (the heart) -- with more image groups planned; the group row is already
/// the future selector. Tap places an item on the canvas, long-press
/// removes it from the shelf. Global across memories.
struct LibraryPanelScene: View {
    @Bindable var editor: CanvasViewModel
    var actions = EditorActions()

    @State private var favorites: [GeneratedSticker] = []

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        EditorScaffold(
            title: "Saved",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            // Same stage as the Image panel: the page the item will land
            // on, read-only.
            ScrollView(showsIndicators: false) {
                StaticPageView(memory: editor.memory, showsSound: false)
                    .padding(.horizontal, Metrics.screenPadding)
            }
        } bottom: {
            panel
            InputModeBar(active: .library, onSelect: actions.selectMode)
        }
        .onAppear {
            // Same hygiene as the old favorites row: entries whose image
            // file is gone or degenerate would render as blank squares.
            favorites = favoritesStore.pruned(imageSide: { name in
                guard let image = CanvasImageCache.image(
                    fileName: name, filterName: "", store: imageStore
                ) else { return nil }
                return min(image.size.width, image.size.height)
            })
        }
    }

    private var panel: some View {
        ContextCard(
            title: "Saved",
            subtitle: favorites.isEmpty
                ? "Things you save land here for reuse."
                : "Tap to place on the page. Hold to remove."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // The group row: Favorites is the only group today, but this
                // is where more image groups will line up.
                HStack(spacing: 8) {
                    Chip(text: "Favorites", selected: true, systemImage: "heart")
                    Spacer()
                }

                if favorites.isEmpty {
                    Label(
                        "Long-press any image or sticker on the canvas and choose Favorite to keep it here.",
                        systemImage: "heart"
                    )
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(favorites) { favorite in
                                Button {
                                    place(favorite)
                                } label: {
                                    thumb(favorite)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("library.item.\(favorite.id.uuidString)")
                                .contextMenu {
                                    Button(role: .destructive) {
                                        remove(favorite)
                                    } label: {
                                        Label("Remove from Favorites", systemImage: "heart.slash")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                }
            }
        }
    }

    /// Tap-to-place: stickers come back as stickers, photos as photos.
    private func place(_ favorite: GeneratedSticker) {
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 80, 4000))
        switch favorite.kind {
        case .sticker:
            editor.addSticker(favorite, at: position)
        case .image:
            editor.addImages(
                [ImageRef(displayName: favorite.prompt, fileName: favorite.fileName)],
                around: position
            )
        }
        actions.leading()
    }

    private func remove(_ favorite: GeneratedSticker) {
        favoritesStore.remove(id: favorite.id)
        favorites = favoritesStore.all()
    }

    @ViewBuilder private func thumb(_ favorite: GeneratedSticker) -> some View {
        if let image = CanvasImageCache.image(
            fileName: favorite.fileName, filterName: "", store: imageStore
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paper))
        } else {
            Image(systemName: favorite.symbolName)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .foregroundStyle(Palette.taupe)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paper))
        }
    }
}
