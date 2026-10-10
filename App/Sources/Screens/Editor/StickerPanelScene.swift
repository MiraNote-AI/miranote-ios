import MiraNoteKit
import SwiftUI

/// The Sticker panel, the bar's fifth tool (2026-10-07 handoff): make a
/// sticker with AI, or reuse a saved favorite. A made sticker is placed the
/// same way as a generated picture -- the canvas asks where it goes. Saved
/// favorites are global across memories: tap places one, long-press removes it.
struct StickerPanelScene: View {
    @Bindable var editor: CanvasViewModel
    var studio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()
    /// Set when a made sticker is waiting for the canvas tap that places it.
    @Binding var pendingPlacement: PendingPlacement?

    @State private var favorites: [GeneratedSticker] = []
    @State private var prompt = ""
    @State private var results: [GeneratedResult] = []
    @State private var generating = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        EditorScaffold(
            title: "Sticker",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            // Same stage as the Image panel: the page the sticker will land
            // on, read-only.
            ScrollView(showsIndicators: false) {
                StaticPageView(memory: editor.memory, showsSound: false)
                    .padding(.horizontal, Metrics.screenPadding)
            }
        } bottom: {
            panel
            InputModeBar(active: .sticker, onSelect: actions.selectMode)
        }
        .onAppear {
            // Entries whose image file is gone or degenerate would render as
            // blank squares.
            favorites = favoritesStore.pruned(imageSide: { name in
                guard let image = CanvasImageCache.image(
                    fileName: name, filterName: "", store: imageStore
                ) else { return nil }
                return min(image.size.width, image.size.height)
            })
        }
    }

    private var panel: some View {
        ContextCard(title: "Sticker", subtitle: "Make one with Mira, or reuse a favorite.") {
            VStack(alignment: .leading, spacing: 12) {
                createRow

                if !results.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            Button {
                                place(result)
                            } label: {
                                thumb(data: result.data)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sticker.result.\(index)")
                        }
                        Spacer()
                    }
                }

                if let notice {
                    Text(notice)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }

                favoritesSection
            }
        }
    }

    // MARK: Make

    private var createRow: some View {
        HStack(spacing: 8) {
            TextField("Describe a sticker", text: $prompt)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.go)
                .onSubmit(generate)
                .accessibilityIdentifier("sticker.prompt")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Palette.paper)
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )

            Button(generating ? "Working..." : "Generate", action: generate)
                .buttonStyle(PrimaryPill(horizontalPadding: 16, verticalPadding: 9))
                .disabled(generating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("sticker.generate.run")
        }
    }

    private func generate() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !generating else { return }
        generating = true
        notice = nil
        results = []
        Task {
            defer { generating = false }
            do {
                let batch = try await studio.generateStickers(prompt: trimmed)
                let images = batch.images
                // Worded off the counts rather than assuming two: the backend
                // returns NUMBER_OF_IMAGES of them and that has already been
                // 1 and 2 at different times.
                if !batch.allMatted {
                    notice = batch.unmatted.count == images.count
                        ? (images.count == 1
                            ? "Couldn't lift this off its background -- it's here as it came."
                            : "Couldn't lift these off their background -- they're here as they came.")
                        : "One of these kept its background. They're all here -- pick either."
                }
                results = images.map { GeneratedResult(data: $0, prompt: trimmed) }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "Making a sticker didn't work this time. Try again?"
            }
        }
    }

    /// Picked, not yet placed: the bytes are saved here (so a write failure is
    /// reported next to the panel that produced it), then the canvas is asked
    /// where it goes.
    private func place(_ result: GeneratedResult) {
        guard let fileName = try? imageStore.save(result.data, id: UUID()) else {
            notice = "That sticker couldn't be saved. Try again?"
            return
        }
        pendingPlacement = PendingPlacement(prompt: result.prompt, fileName: fileName, isSticker: true)
        actions.leading()
    }

    // MARK: Favorites

    @ViewBuilder private var favoritesSection: some View {
        Label("Favorites", systemImage: "heart")
            .font(.miraLabel)
            .foregroundStyle(Palette.ink)

        if favorites.isEmpty {
            Text("Long-press any image or sticker on the canvas and choose Favorite to keep it here.")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(favorites) { favorite in
                        Button {
                            place(favorite)
                        } label: {
                            favoriteThumb(favorite)
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
            .frame(maxHeight: 150)
        }
    }

    /// Tap-to-place: stickers come back as stickers, photos as photos.
    private func place(_ favorite: GeneratedSticker) {
        let centerX = MiraNoteConfig.pageWidth / 2
        switch favorite.kind {
        case .sticker:
            let position = CGPoint(x: centerX, y: min(editor.contentBottom + 80, 4000))
            editor.addSticker(favorite, at: position)
        case .image:
            // Re-adopt the photo's aspect so a saved original comes back the
            // shape it went in, not center-cropped into the default box.
            var box = CGSize(width: 170, height: 150)
            if let image = CanvasImageCache.image(
                fileName: favorite.fileName, filterName: "", store: imageStore
            ) {
                box = CanvasImageCache.aspectBox(for: image)
            }
            let position = CGPoint(x: centerX, y: min(editor.contentBottom + 60 + box.height / 2, 4000))
            editor.addImages(
                [ImageRef(displayName: favorite.prompt, fileName: favorite.fileName)],
                around: position, size: box
            )
        }
        actions.leading()
    }

    private func remove(_ favorite: GeneratedSticker) {
        favoritesStore.remove(id: favorite.id)
        favorites = favoritesStore.all()
    }

    // MARK: Thumbnails

    private func thumb(data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Palette.cardFill
            }
        }
        .frame(width: 56, height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    @ViewBuilder private func favoriteThumb(_ favorite: GeneratedSticker) -> some View {
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
