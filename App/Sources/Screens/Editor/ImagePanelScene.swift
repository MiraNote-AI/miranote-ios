import MiraNoteKit
import PhotosUI
import SwiftUI

/// The Image panel (v2.1): three sources -- Library, Camera, Generate --
/// with sticker creation living inside Generate as a style, and the
/// "My stickers" favorites row always in view.
struct ImagePanelScene: View {
    @Bindable var editor: CanvasViewModel
    var studio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()

    /// Generate is the only mode-like source; Library and Camera act
    /// directly from their buttons (one row, no second step).
    @State private var generateOpen = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var prompt = ""
    @State private var style: GenerateStyle = .photo
    @State private var results: [GeneratedResult] = []
    @State private var generating = false
    @State private var notice: String?
    @State private var favorites: [GeneratedSticker] = []

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        EditorScaffold(
            title: "Add an image",
            onLeading: actions.leading,
            onTrailing: actions.done
        ) {
            // The user's own page, not a demo: what the picked image will
            // land on. Read-only up here; the canvas stays the editor.
            ScrollView(showsIndicators: false) {
                StaticPageView(memory: editor.memory, showsSound: false)
                    .padding(.horizontal, Metrics.screenPadding)
            }
        } bottom: {
            panel
            InputModeBar(active: .image, onSelect: actions.selectMode)
        }
        .onAppear {
            // Hygiene on open: favorites whose image is gone or degenerate
            // (mock-era 8x8 debris) would render as blank squares.
            favorites = favoritesStore.pruned(imageSide: { name in
                guard let image = CanvasImageCache.image(
                    fileName: name, filterName: "", store: imageStore
                ) else { return nil }
                return min(image.size.width, image.size.height)
            })
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPicked(items)
        }
        .sheet(isPresented: $showsCamera) {
            CameraCapture { image in
                add(imageData: image.downscaled(), name: "Camera photo")
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Panel

    private var panel: some View {
        ContextCard(
            title: "Add an image",
            subtitle: "Pick from your library, take a photo, or generate one."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // One row, three direct actions -- no picking a source
                // first ("Library" then "Choose from Library" confused).
                HStack(spacing: 8) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: MiraNoteConfig.maxImagesPerAdd,
                        matching: .images
                    ) {
                        Chip(text: "Library")
                    }
                    .accessibilityIdentifier("image.library.pick")

                    Button {
                        if CameraCapture.isAvailable {
                            showsCamera = true
                        } else {
                            notice = "The camera isn't available here."
                        }
                    } label: {
                        Chip(text: "Camera")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("image.camera.open")

                    Button {
                        generateOpen.toggle()
                    } label: {
                        Chip(text: "AI image", selected: generateOpen, systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("image.source.generate")

                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-UITEST") {
                        Button {
                            addSamplePhotos()
                        } label: {
                            Chip(text: "Samples")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("image.library.samples")
                    }
                    #endif
                    Spacer()
                }

                if generateOpen {
                    generateRows
                }

                if let notice {
                    Text(notice)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }

                if !favorites.isEmpty {
                    favoritesRow
                }
            }
        }
    }

    private func importPicked(_ items: [PhotosPickerItem]) {
        Task {
            var added = false
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let scaled = UIImage(data: data)?.downscaled() else { continue }
                add(imageData: scaled, name: "Library photo", returnToCanvas: false)
                added = true
            }
            pickerItems = []
            if added {
                actions.leading()
            } else {
                notice = "Those photos couldn't be imported. Try different ones?"
            }
        }
    }

    #if DEBUG
    /// -UITEST only: two canned images straight through the real pipeline.
    /// The second is portrait so tests can lock aspect-true boxes and
    /// overflow-free rendering.
    private func addSamplePhotos() {
        add(imageData: MockImageStudioService.tinyPNG, name: "Sample one", returnToCanvas: false)
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 16)).pngData { context in
            UIColor(red: 0.79, green: 0.70, blue: 0.58, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        }
        add(imageData: tall, name: "Sample two", returnToCanvas: false)
        actions.leading()
    }
    #endif
}

// MARK: - Generate and favorites

extension ImagePanelScene {
    // MARK: Generate

    @ViewBuilder private var generateRows: some View {
        // Style first, words second: these chips pick what KIND of picture
        // the AI paints (sticker included, per v2.1), not a photo filter.
        Text("STYLE")
            .font(.system(size: 10, weight: .medium))
            .kerning(1.4)
            .foregroundStyle(Palette.textSecondary)

        HStack(spacing: 8) {
            ForEach(GenerateStyle.allCases) { choice in
                Button {
                    style = choice
                } label: {
                    Chip(text: choice.label, selected: style == choice, compact: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("image.style.\(choice.rawValue)")
            }
            Spacer()
        }

        HStack(spacing: 8) {
            TextField("Describe the picture you want", text: $prompt)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .accessibilityIdentifier("image.prompt")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Palette.paper)
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )

            Button {
                generate()
            } label: {
                pillLabel(generating ? "Working..." : "Generate")
            }
            .buttonStyle(.plain)
            .disabled(generating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("image.generate.run")
        }

        if !results.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        place(result)
                    } label: {
                        thumb(result.data)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("image.result.\(index)")
                }
                Spacer()
            }
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
                let images = try await studio.generate(kind: style.kind, prompt: style.fullPrompt(trimmed))
                results = images.map { GeneratedResult(data: $0, prompt: trimmed, style: style) }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "Generating didn't work this time. Try again?"
            }
        }
    }

    private func place(_ result: GeneratedResult) {
        guard let fileName = try? imageStore.save(result.data, id: UUID()) else {
            notice = "That picture couldn't be saved. Try again?"
            return
        }
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 90, 4000))
        if result.style == .sticker {
            let sticker = GeneratedSticker(prompt: result.prompt, symbolName: "sparkles", fileName: fileName)
            editor.addSticker(sticker, at: position)
            favoritesStore.add(sticker)
            favorites = favoritesStore.all()
        } else {
            editor.addImages([ImageRef(displayName: result.prompt, fileName: fileName)], around: position)
        }
        actions.leading()
    }

    // MARK: Favorites

    private var favoritesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MY STICKERS")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .kerning(1.4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(favorites) { sticker in
                        Button {
                            placeFavorite(sticker)
                        } label: {
                            favoriteThumb(sticker)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("image.favorite.\(sticker.id.uuidString)")
                    }
                }
            }
        }
    }

    private func placeFavorite(_ sticker: GeneratedSticker) {
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 80, 4000))
        editor.addSticker(sticker, at: position)
        actions.leading()
    }

    @ViewBuilder private func favoriteThumb(_ sticker: GeneratedSticker) -> some View {
        if let image = CanvasImageCache.image(fileName: sticker.fileName, filterName: "", store: imageStore) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paper))
        } else {
            Image(systemName: sticker.symbolName)
                .frame(width: 44, height: 44)
                .foregroundStyle(Palette.taupe)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paper))
        }
    }

    // MARK: Shared bits

    private func add(imageData: Data?, name: String, returnToCanvas: Bool = true) {
        guard let imageData,
              let fileName = try? imageStore.save(imageData, id: UUID()) else {
            notice = "That photo couldn't be saved. Try again?"
            return
        }
        // Photos sway left-center-right as they stack down the page --
        // a hand-placed column, not a machine pile. Deterministic on the
        // existing photo count so tests stay stable.
        let photoCount = editor.items.filter {
            if case .image = $0.content { return true } else { return false }
        }.count
        let sway: CGFloat = [-28, 0, 28][photoCount % 3]
        // The box adopts the photo's aspect (within taste) so portrait
        // shots arrive tall instead of center-cropped into a landscape.
        var box = CGSize(width: 170, height: 150)
        if let ui = UIImage(data: imageData), ui.size.width > 0 {
            let aspect = ui.size.height / ui.size.width
            box = CGSize(width: 170, height: min(260, max(110, (170 * aspect).rounded())))
        }
        let position = CGPoint(x: 180 + sway, y: min(editor.contentBottom + 60 + box.height / 2, 4000))
        let ids = editor.addImages(
            [ImageRef(displayName: name, fileName: fileName)], around: position, size: box
        )
        describeInBackground(itemID: ids.first, imageData: imageData)
        if returnToCanvas { actions.leading() }
    }

    /// Vision looks at the photo once, off the main path; the sentence
    /// becomes page context so chat can "see" the picture. Best-effort.
    private func describeInBackground(itemID: CanvasItem.ID?, imageData: Data) {
        guard let itemID else { return }
        Task {
            guard let summary = try? await studio.describe(image: imageData) else { return }
            editor.setImageSummary(itemID: itemID, to: summary)
        }
    }

    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.miraLabel)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.ink))
    }

    private func thumb(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Palette.cardFill
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }
}
