import CoreImage
import MiraNoteKit
import SwiftUI

/// The Sticker panel, the bar's fifth tool (handoff screens 30-35): a glass
/// sheet over the scrimmed page with a scrolling tab row -- Make, Favorites,
/// then the preset sets -- and the generate prompt in the bottom composer.
/// A made sticker shows large, restyles (Outline / Cutout / B&W) with its
/// own undo and redo, and Add hands it to the canvas, which asks where it
/// goes. Favorites and presets place on a tap.
struct StickerPanelScene: View {
    @Bindable var editor: CanvasViewModel
    var studio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()
    /// Set when a made sticker is waiting for the canvas tap that places it.
    @Binding var pendingPlacement: PendingPlacement?

    enum Tab: Hashable {
        case make, favorites
        case set(StickerSet.ID)

        var accessibilityID: String {
            switch self {
            case .make: return "sticker.tab.make"
            case .favorites: return "sticker.tab.favorites"
            case .set(let id): return "sticker.tab.\(id)"
            }
        }
    }

    @State private var tab: Tab = .make
    @State private var favorites: [GeneratedSticker] = []
    @State private var prompt = ""
    @State private var drafts: [StickerDraft] = []
    @State private var page = 0
    @State private var generating = false
    /// A style tile's studio call in flight.
    @State private var styling = false
    @State private var notice: String?
    /// While typing, the sheet folds to its collapsed height: the keyboard
    /// leaves no room for 430 above the composer.
    @FocusState private var promptFocused: Bool

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        EditorScaffold(
            leading: "Cancel",
            trailing: "Add",
            onLeading: actions.leading,
            onTrailing: add,
            // The panel records no step of its own (presets and favorites
            // leave it as they place; a made sticker has its own undo): the
            // header Undo has nothing here, never a change under the scrim.
            onUndo: {},
            undoEnabled: false,
            scrimmed: true,
            onScrimTap: {
                // While the prompt has the keyboard, a tap on the page only
                // lowers it: leaving would drop the words.
                if promptFocused {
                    promptFocused = false
                    return
                }
                // A tap on the page goes back to it -- except while a
                // sticker is being made or waits to be added: it took
                // seconds and real credits, and leaving would drop it.
                guard !placingWouldDropWork else { return }
                actions.leading()
            }
        ) {
            // The page the sticker will land on, read-only under the scrim.
            PagePreview(memory: editor.memory) {}
        } sheet: {
            sheet
                .frame(height: sheetHeight)
                .animation(.spring(response: 0.35), value: sheetHeight)
                // A tap on the sheet lowers the prompt's keyboard.
                .onTapGesture { promptFocused = false }
        } bottom: {
            InputModeBar(active: .sticker, onSelect: { mode in
                // Another tool leaves the panel: same rule as the presets.
                guard mode == .sticker || !placingWouldDropWork else {
                    notice = "Add the sticker you made first, or Cancel to let it go."
                    return
                }
                actions.selectMode(mode)
            })
            ToolComposer(
                placeholder: "Ask mira to generate a sticker",
                text: $prompt,
                action: "Generate",
                actionWidth: 74,
                actionEnabled: canGenerate,
                fieldID: "sticker.prompt",
                actionID: "sticker.generate.run",
                focus: $promptFocused,
                onAction: generate
            )
        }
        .onAppear {
            // Entries whose image file is gone or degenerate would render as
            // blank squares.
            favorites = favoritesStore.prunedRaisingSmall(images: imageStore)
        }
        #if DEBUG
        .background(DebugStateProbe {
            ["scene": "sticker", "listening": [String: Bool](), "busy": busy, "drafts": drafts.count,
             "undoDepth": editor.undoDepth, "writing": editor.editingTextItemID?.uuidString ?? ""]
        })
        #endif
    }

    private var busy: Bool { generating || styling }

    /// A favorite or preset tap places it and leaves the panel, which would
    /// drop a sticker being made or waiting to be added -- it took seconds
    /// and real credits (#93).
    private var placingWouldDropWork: Bool { busy || !drafts.isEmpty }

    /// Collapsed 147 at rest (screen 30); 430 while making or showing a
    /// sticker (32-33); 420 for a full grid (34-35).
    private var sheetHeight: CGFloat {
        if promptFocused { return 147 }
        switch tab {
        case .make: return showsWork ? 430 : 147
        case .favorites: return favorites.isEmpty ? 147 : 420
        case .set: return 420
        }
    }

    // MARK: Sheet

    private var sheet: some View {
        GlassSheet(title: "Sticker", border: Color(hex: 0xEEEEE9)) {
            VStack(alignment: .leading, spacing: 0) {
                tabRow
                Group {
                    switch tab {
                    case .make: makeTab
                    case .favorites: favoritesTab
                    case .set(let id): setTab(StickerSet.all.first { $0.id == id } ?? .food)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    /// 47 x 41 r18 tiles at y 56, pitch 58; the row scrolls past the edge.
    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 11) {
                tabTile(.make, label: "Make a sticker") {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.ink)
                }
                tabTile(.favorites, label: "Favorites") {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.forest)
                }
                ForEach(StickerSet.all) { set in
                    tabTile(.set(set.id), label: set.title) {
                        Image(set.imageName(set.hero))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 30)
                    }
                }
            }
            .padding(.horizontal, 21)
            .padding(.vertical, 1)
        }
        .padding(.horizontal, -21)
        .padding(.top, 3)
    }

    private func tabTile<Icon: View>(_ value: Tab, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        let active = tab == value
        let shape = RoundedRectangle(cornerRadius: 18)
        return Button {
            tab = value
        } label: {
            icon()
                .frame(width: 47, height: 41)
                .background(shape.fill(Palette.cardFill))
                .overlay(shape.strokeBorder(active ? Palette.ink : .clear, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(value.accessibilityID)
    }

    // MARK: Make

    /// Something is being made or waits to be added, and there is room to show it.
    private var showsWork: Bool { (generating || !drafts.isEmpty) && !promptFocused }

    @ViewBuilder private var makeTab: some View {
        if showsWork {
            VStack(alignment: .leading, spacing: 0) {
                cluster
                    .padding(.top, 27)
                    .padding(.leading, 2)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                styleTiles
                    .padding(.leading, 2)
            }
            .padding(.bottom, -4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if generating || !drafts.isEmpty {
                    Text("Generate makes a new one; close the keyboard to see this one.")
                        .font(.miraComposer)
                        .foregroundStyle(Palette.textSecondary)
                } else if let photo = selectedPhoto {
                    photoShortcut(photo)
                } else {
                    Text("Describe a sticker below -- Mira makes a couple to pick from.")
                        .font(.miraComposer)
                        .foregroundStyle(Palette.textSecondary)
                }
                noticeLine
            }
            .padding(.top, 12)
        }
    }

    /// Screen 30: the photo selected on the canvas, a tap from becoming a
    /// sticker (cutout, then outline).
    private func photoShortcut(_ photo: ImageRef) -> some View {
        Button {
            makeSticker(from: photo)
        } label: {
            Group {
                if let image = CanvasImageCache.image(
                    fileName: photo.fileName, filterName: photo.filterName, store: imageStore
                ) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    GradientPlaceholder()
                }
            }
            .frame(width: 38, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.ink, lineWidth: 3))
            .padding(.leading, 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a sticker from the selected photo")
        .accessibilityIdentifier("sticker.fromPhoto")
    }

    /// The photo selected on the canvas, if it has pixels to cut.
    private var selectedPhoto: ImageRef? {
        guard let id = editor.selectedItemID,
              case .image(let ref) = editor.item(id)?.content,
              !ref.fileName.isEmpty else { return nil }
        return ref
    }

    /// Screens 32-33: Undo / Redo / Favorite, 34 ink circles, pitch 43.5.
    private var cluster: some View {
        let draft = drafts.indices.contains(page) ? drafts[page] : nil
        return HStack(spacing: 9.5) {
            Button {
                drafts[page].index -= 1
            } label: {
                FloatingCircle { FloatingGlyph.undo() }
            }
            .disabled(busy || !(draft?.canUndo ?? false))
            .accessibilityLabel("Undo style")
            .accessibilityIdentifier("sticker.undo")

            Button {
                drafts[page].index += 1
            } label: {
                FloatingCircle { FloatingGlyph.undo(mirrored: true) }
            }
            .disabled(busy || !(draft?.canRedo ?? false))
            .accessibilityLabel("Redo style")
            .accessibilityIdentifier("sticker.redo")

            Button(action: favoriteCurrent) {
                FloatingCircle { FloatingGlyph.favorite(saved: draft?.current.favorite ?? false) }
            }
            .disabled(busy || draft == nil || (draft?.current.favorite ?? false))
            .accessibilityLabel("Add to Favorites")
            .accessibilityIdentifier("sticker.favorite")
        }
        .buttonStyle(.plain)
    }

    /// The made sticker, large (232 at most); several page sideways.
    @ViewBuilder private var preview: some View {
        if generating {
            DotRingSpinner()
                .accessibilityIdentifier("sticker.generating")
        } else if drafts.count == 1 {
            draftImage(drafts[0], index: 0)
        } else {
            TabView(selection: $page) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    draftImage(draft, index: index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    private func draftImage(_ draft: StickerDraft, index: Int) -> some View {
        ZStack {
            Group {
                if let image = UIImage(data: draft.current.data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Palette.cardFill
                }
            }
            .frame(maxWidth: 232, maxHeight: 232)
            .accessibilityElement()
            .accessibilityLabel(draft.prompt)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("sticker.result.\(index)")
            if styling && index == page {
                DotRingSpinner(diameter: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Outline / Cutout / B&W (the design's "Jeans" is undefined and left
    /// out); the tile that made the showing variant is lit.
    private var styleTiles: some View {
        let style = drafts.indices.contains(page) ? drafts[page].current.style : nil
        return VStack(alignment: .leading, spacing: 6) {
            noticeLine
            HStack(spacing: 14) {
                ForEach(StickerLook.allCases) { choice in
                    EditTile(label: choice.label, selected: style == choice, selectedFill: Palette.cardFill) {
                        restyle(choice)
                    }
                    .disabled(busy || drafts.isEmpty)
                    .accessibilityIdentifier("sticker.style.\(choice.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private var noticeLine: some View {
        if let notice {
            Text(notice)
                .font(.miraComposer)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sticker.notice")
        }
    }

    // MARK: Favorites (screen 34) and sets (screen 35)

    @ViewBuilder private var favoritesTab: some View {
        if favorites.isEmpty {
            Text("Long-press any image or sticker on the canvas and choose Favorite to keep it here.")
                .font(.miraComposer)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 12)
        } else {
            waitingWorkLine
            ScrollView(showsIndicators: false) {
                // Five 60 pt cells across the sheet (screen 34).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 50, maximum: 60), spacing: 4),
                                         count: 5),
                          spacing: 9) {
                    ForEach(favorites) { favorite in
                        Button {
                            place(favorite)
                        } label: {
                            favoriteThumb(favorite)
                        }
                        .buttonStyle(.plain)
                        .disabled(placingWouldDropWork)
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
                .padding(.top, 6)
            }
            .padding(.leading, -4)
        }
    }

    /// Why favorites and presets are dimmed while a made sticker waits.
    @ViewBuilder private var waitingWorkLine: some View {
        if placingWouldDropWork {
            Text("Add the sticker you made first, or Cancel to let it go.")
                .font(.miraComposer)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 10)
                .accessibilityIdentifier("sticker.waiting")
        }
    }

    private func setTab(_ set: StickerSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            waitingWorkLine
            setGrid(set)
        }
    }

    private func setGrid(_ set: StickerSet) -> some View {
        ScrollView(showsIndicators: false) {
            // Five 50 pt stickers across the sheet, rows 60 apart (screen 35).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 13), count: 5),
                      spacing: 10) {
                ForEach(set.names, id: \.self) { name in
                    Button {
                        place(name, from: set)
                    } label: {
                        Image(set.imageName(name))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(placingWouldDropWork)
                    .opacity(placingWouldDropWork ? 0.45 : 1)
                    .accessibilityLabel(name.replacingOccurrences(of: "-", with: " "))
                    .accessibilityIdentifier("sticker.preset.\(name)")
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .padding(.leading, 1)
    }

    @ViewBuilder private func favoriteThumb(_ favorite: GeneratedSticker) -> some View {
        let image = CanvasImageCache.image(fileName: favorite.fileName, filterName: "", store: imageStore)
        switch favorite.kind {
        case .image:
            // Photos as the handoff draws them: 38 x 36 r18, ink border.
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    GradientPlaceholder()
                }
            }
            .frame(width: 38, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.ink, lineWidth: 3))
            .frame(width: 60, height: 60)
        case .sticker:
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: favorite.symbolName)
                        .foregroundStyle(Palette.taupe)
                }
            }
            .frame(width: 60, height: 60)
        }
    }

    // MARK: Actions

    private var canGenerate: Bool {
        !busy && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generate() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        generating = true
        notice = nil
        drafts = []
        page = 0
        // What is being made shows on the Make tab, at full height.
        tab = .make
        promptFocused = false
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
                if images.isEmpty {
                    notice = "Mira couldn't make that one -- try other words?"
                }
                drafts = images.map { StickerDraft(prompt: trimmed, data: $0) }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "Making a sticker didn't work this time. Try again?"
            }
        }
    }

    private func makeSticker(from photo: ImageRef) {
        guard !busy, let data = imageStore.data(forFileName: photo.fileName) else { return }
        generating = true
        notice = nil
        drafts = []
        page = 0
        Task {
            defer { generating = false }
            do {
                let cut = try await studio.cutout(image: data, target: nil)
                let outlined = try await studio.outline(image: cut)
                var draft = StickerDraft(prompt: photo.displayName, data: cut, style: .cutout)
                draft.push(StickerVariant(data: outlined, style: .outline))
                drafts = [draft]
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }

    private func restyle(_ style: StickerLook) {
        guard !busy, drafts.indices.contains(page) else { return }
        let index = page
        let source = drafts[index].current.data
        let target = drafts[index].prompt
        styling = true
        notice = nil
        Task {
            defer { styling = false }
            do {
                let restyled: Data
                switch style {
                case .outline: restyled = try await studio.outline(image: source)
                case .cutout: restyled = try await studio.cutout(image: source, target: target)
                case .bw:
                    guard let mono = StickerLook.monochrome(source) else {
                        notice = "That didn't work this time. Try again?"
                        return
                    }
                    restyled = mono
                }
                guard drafts.indices.contains(index) else { return }
                drafts[index].push(StickerVariant(data: restyled, style: style))
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }

    private func favoriteCurrent() {
        guard drafts.indices.contains(page),
              let fileName = try? imageStore.save(drafts[page].current.data, id: UUID()) else { return }
        favoritesStore.add(GeneratedSticker(prompt: drafts[page].prompt, symbolName: "sparkles", fileName: fileName))
        drafts[page].markFavorite()
        favorites = favoritesStore.all()
    }

    /// Nav Add: the showing sticker goes to the canvas, which asks where.
    /// With nothing made, Add simply returns to the page.
    private func add() {
        guard !busy, drafts.indices.contains(page) else {
            if !busy { actions.leading() }
            return
        }
        // Saved here, so a write failure is reported next to the sticker.
        guard let fileName = try? imageStore.save(drafts[page].current.data, id: UUID()) else {
            notice = "That sticker couldn't be saved. Try again?"
            return
        }
        pendingPlacement = PendingPlacement(prompt: drafts[page].prompt, fileName: fileName, isSticker: true)
        actions.leading()
    }

    /// Tap-to-place: stickers come back as stickers, photos as photos.
    private func place(_ favorite: GeneratedSticker) {
        guard !placingWouldDropWork else { return }
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

    /// A preset sticker: its bundled pixels are stored like a made one (at
    /// least `StickerSet.minPlacedSide` on the short side), then it lands
    /// centred below the page's content.
    private func place(_ name: String, from set: StickerSet) {
        guard !placingWouldDropWork, let data = set.placeableData(name),
              let fileName = try? imageStore.save(data, id: UUID()) else { return }
        let position = CGPoint(x: MiraNoteConfig.pageWidth / 2, y: min(editor.contentBottom + 80, 4000))
        editor.addSticker(
            GeneratedSticker(prompt: name.replacingOccurrences(of: "-", with: " "),
                             symbolName: "sparkles", fileName: fileName),
            at: position
        )
        actions.leading()
    }

    private func remove(_ favorite: GeneratedSticker) {
        favoritesStore.remove(id: favorite.id)
        favorites = favoritesStore.all()
    }
}

// MARK: - Drafts

/// The sticker style tiles of screens 32-33.
enum StickerLook: String, CaseIterable, Identifiable {
    case outline, cutout, bw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .outline: return "Outline"
        case .cutout: return "Cutout"
        case .bw: return "B&W"
        }
    }

    private static let context = CIContext()

    /// Black and white that keeps the sticker's transparent edges.
    static func monochrome(_ data: Data) -> Data? {
        guard let input = CIImage(data: data) else { return nil }
        let output = PhotoFilter.bw.apply(to: input)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

/// One look of a made sticker; nil style is as it came from the studio.
struct StickerVariant {
    let data: Data
    let style: StickerLook?
    var favorite = false
}

/// A made sticker and its style history: the floating Undo and Redo step
/// through it, a new style drops what was undone.
struct StickerDraft: Identifiable {
    let id = UUID()
    let prompt: String
    private(set) var variants: [StickerVariant]
    var index: Int

    init(prompt: String, data: Data, style: StickerLook? = nil) {
        self.prompt = prompt
        variants = [StickerVariant(data: data, style: style)]
        index = 0
    }

    var current: StickerVariant { variants[index] }
    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index < variants.count - 1 }

    mutating func push(_ variant: StickerVariant) {
        variants.removeSubrange((index + 1)...)
        variants.append(variant)
        index = variants.count - 1
    }

    mutating func markFavorite() {
        variants[index].favorite = true
    }
}
