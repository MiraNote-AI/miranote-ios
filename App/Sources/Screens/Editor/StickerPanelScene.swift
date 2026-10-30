import CoreImage
import MiraNoteKit
import SwiftUI

/// The Sticker panel, the bar's fifth tool (handoff screens 30-35): a glass
/// sheet over the scrimmed page with a scrolling tab row -- Make, Favorites,
/// then the preset sets -- and the generate prompt in the bottom composer.
/// A made sticker shows large, restyles (Outline / Cutout / B&W) with its
/// own undo and redo; "Add to page" under it (or a tap on it) hops it onto a
/// free spot of the page in view. Favorites and presets place on a tap.
struct StickerPanelScene: View {
    @Bindable var editor: CanvasViewModel
    var studio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()
    /// The made sticker on its way to the canvas, with its landing spot.
    @Binding var pendingPlacement: PendingPlacement?
    /// Where the canvas stood: the preview opens there, and Add lands there.
    var scrollMemory = CanvasScrollMemory()

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
    /// The page's card row and the made sticker's preview, on screen: the
    /// hop runs from one onto the other.
    @State private var pageRow: CGRect = .zero
    @State private var previewFrame: CGRect = .zero
    /// The sticker in its hop, and what it hands the canvas when it lands.
    @State private var flight: Flight?
    @State private var flightPending: PendingPlacement?
    /// While typing, the sheet folds to its collapsed height: the keyboard
    /// leaves no room for the full sheet (500 while showing a sticker, 420
    /// for a grid).
    @FocusState private var promptFocused: Bool

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        EditorScaffold(
            leading: "Cancel",
            // The sheet's "Add to page" is the way a made sticker goes in
            // (owner, 2026-10-19): no second Add while one shows or is on
            // its way. With none, the header Add returns to the page.
            trailing: generating || !drafts.isEmpty ? nil : "Add",
            onLeading: actions.leading,
            onTrailing: actions.leading,
            // The panel records no step of its own (presets and favorites
            // leave it as they place; a made sticker has its own undo): the
            // header Undo has nothing here, never a change under the scrim.
            onUndo: {},
            undoEnabled: false,
            // The hopping sticker shows the page it lands on.
            scrimmed: flight == nil,
            onScrimTap: {
                // While the prompt has the keyboard and words in it, a tap
                // on the page only lowers it: leaving would drop the words.
                if promptFocused && !prompt.isEmpty {
                    promptFocused = false
                    return
                }
                // A tap on the page goes back to it -- except while a
                // sticker is being made or waits to be added: it took
                // seconds and real credits, and leaving would drop it. The
                // tap then only lowers the keyboard.
                guard !placingWouldDropWork else {
                    promptFocused = false
                    return
                }
                actions.leading()
            }
        ) {
            // The page the sticker will land on, read-only under the scrim.
            PagePreview(memory: editor.memory, scroll: scrollMemory) {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pageRow = $0 }
        } sheet: {
            sheet
                .frame(height: sheetHeight)
                .animation(.spring(response: 0.35), value: sheetHeight)
                // A tap on the sheet lowers the prompt's keyboard.
                .onTapGesture { promptFocused = false }
                // The sheet slides away under the hopping sticker.
                .offset(y: flight == nil ? 0 : 700)
                .animation(.easeIn(duration: Self.hop), value: flight == nil)
        } bottom: {
            InputModeBar(active: .sticker, onSelect: { mode in
                // Another tool leaves the panel: same rule as the presets.
                guard mode == .sticker || !placingWouldDropWork else {
                    notice = String(appCopy: "Add the sticker you made first, or Cancel to let it go.")
                    return
                }
                actions.selectMode(mode)
            })
            ToolComposer(
                placeholder: "Describe a sticker",
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
        .overlay {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                if let flight {
                    Image(uiImage: flight.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: flight.side, height: flight.side)
                        .shadow(color: Palette.ink.opacity(0.25), radius: 12, y: 8)
                        .position(x: flight.x - origin.x, y: flight.y - origin.y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea()
            .overlay {
                // No waiting on the hop: a touch lands it now.
                if flight != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in land() })
                }
            }
        }
        .onAppear {
            // Entries whose image file is gone or degenerate would render as
            // blank squares.
            favorites = favoritesStore.prunedRaisingSmall(images: imageStore)
            // A cut-out is likely next: load Vision's model now, not on it.
            studio.prepare()
        }
        #if DEBUG
        .background(DebugStateProbe {
            ["scene": "sticker", "listening": [String: Bool](), "busy": busy, "drafts": drafts.count,
             "undoDepth": editor.undoDepth, "writing": editor.editingTextItemID?.uuidString ?? "",
             "scrollOffset": scrollMemory.offset]
        })
        #endif
    }

    private var busy: Bool { generating || styling }

    /// A favorite or preset tap places it and leaves the panel, which would
    /// drop a sticker being made or waiting to be added -- it took seconds
    /// and real credits (#93).
    private var placingWouldDropWork: Bool { busy || !drafts.isEmpty }

    /// Folded at rest (screen 30), room for two lines of 15 pt help under
    /// the tabs; 500 while making or showing a sticker (32-33, with the
    /// "Add to page" row); 420 for a full grid (34-35).
    private static let folded: CGFloat = 170

    private var sheetHeight: CGFloat {
        if promptFocused { return Self.folded }
        let wanted: CGFloat
        switch tab {
        case .make: wanted = showsWork ? 500 : Self.folded
        case .favorites: wanted = favorites.isEmpty ? Self.folded : 420
        case .set: wanted = 420
        }
        // Never over the header: on a small phone (375 x 667) the card is
        // shorter than 500, and the sheet stays inside it (#127 review).
        guard pageRow.height > 0 else { return wanted }
        return min(wanted, pageRow.height - 2 * Metrics.sheetInCard)
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
        .accessibilityLabel(Text(copy: label))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(value.accessibilityID)
    }

    // MARK: Make

    /// Something is being made or waits to be added, and there is room to show it.
    private var showsWork: Bool { (generating || !drafts.isEmpty) && !promptFocused }

    @ViewBuilder private var makeTab: some View {
        if showsWork {
            VStack(alignment: .leading, spacing: 0) {
                // One rhythm: 16 between the tabs, the undo row, the
                // sticker, the Add row and the style tiles.
                cluster
                    .padding(.top, 16)
                    .padding(.leading, 2)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { previewFrame = $0 }
                    .padding(.top, 8)
                addRow
                styleTiles
                    .padding(.leading, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if generating || !drafts.isEmpty {
                    Text("Generate makes a new one; close the keyboard to see this one.")
                        .font(.miraLabel)
                        .foregroundStyle(Palette.textSecondary)
                } else if let photo = selectedPhoto {
                    photoShortcut(photo)
                } else {
                    Text("Describe a sticker below -- Mira makes a couple to pick from.")
                        .font(.miraLabel)
                        .foregroundStyle(Palette.textSecondary)
                }
                noticeLine
            }
            .padding(.top, 12)
        }
    }

    /// Screen 30: the photo selected on the canvas, a tap from becoming a
    /// sticker (cut out, no edge; the Outline tile adds one).
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

    /// Screens 32-33: Undo / Redo, 34 ink circles, pitch 43.5 (Favorite
    /// sits beside "Add to page").
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
            // One element: VoiceOver reads the prompt and offers Add.
            .accessibilityElement()
            .accessibilityLabel(draft.prompt)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("sticker.result.\(index)")
            // The sticker itself adds, as "Add to page" under it.
            .onTapGesture(perform: add)
            // Gone at once when it takes off: the hopping copy is it.
            .opacity(index == page && flight != nil ? 0 : 1)
            .animation(nil, value: flight == nil)
            .accessibilityAction(named: "Add to page", add)
            if styling && index == page {
                DotRingSpinner(diameter: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Add within thumb reach (owner, 2026-10-19)

    /// Under the made sticker, where the thumb is: a wide "Add to page" and
    /// a compact Favorite beside it.
    private var addRow: some View {
        HStack(spacing: 10) {
            addPill
            favoriteButton
        }
        .padding(.vertical, 16)
    }

    private var addPill: some View {
        Button(action: add) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add to page")
                    .font(.miraPill)
            }
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Capsule().fill(Palette.ink))
            .shadow(color: Palette.ink.opacity(0.16), radius: 10, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.45 : 1)
        .accessibilityIdentifier("sticker.addToPage")
    }

    /// Favorite as the pill's 46 pt paper companion; a filled star once
    /// saved.
    private var favoriteButton: some View {
        let saved = drafts.indices.contains(page) && drafts[page].current.favorite
        return Button(action: favoriteCurrent) {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(saved ? Palette.forest : Palette.ink)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Palette.cardFill))
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy || saved)
        .accessibilityLabel(saved ? Text("In Favorites") : Text("Add to Favorites"))
        .accessibilityIdentifier("sticker.favorite")
    }

    /// The card within the page row, and screen points per page point.
    private var pageCard: (frame: CGRect, scale: CGFloat) {
        let card = pageRow.insetBy(dx: Metrics.canvasInset, dy: 0)
        return (card, CanvasCard.pageScale(rowWidth: pageRow.width))
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
                .font(.miraLabel)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sticker.notice")
        }
    }

    // MARK: Favorites (screen 34) and sets (screen 35)

    @ViewBuilder private var favoritesTab: some View {
        if favorites.isEmpty {
            Text("Long-press any image or sticker on the canvas and choose Favorite to keep it here.")
                .font(.miraLabel)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 12)
        } else {
            // One column: the line, then the grid under it (the Group the
            // tab sits in would frame them apart).
            VStack(alignment: .leading, spacing: 0) {
                waitingWorkLine
                favoritesGrid
            }
        }
    }

    private var favoritesGrid: some View {
        ScrollView(showsIndicators: false) {
            // Five 60 pt cells across the sheet (screen 34).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 50, maximum: 60), spacing: 4), count: 5),
                      spacing: 9) {
                ForEach(favorites) { favorite in
                    Button {
                        place(favorite)
                    } label: {
                        favoriteThumb(favorite)
                    }
                    .buttonStyle(.plain)
                    .disabled(placingWouldDropWork)
                    .opacity(placingWouldDropWork ? 0.45 : 1)
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
            .padding(.top, 12)
        }
        .padding(.leading, -4)
    }

    /// Why favorites and presets are dimmed while a made sticker waits.
    @ViewBuilder private var waitingWorkLine: some View {
        if placingWouldDropWork {
            Text("Add the sticker you made first, or Cancel to let it go.")
                .font(.miraLabel)
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
                    .accessibilityLabel(Text(copy: name.replacingOccurrences(of: "-", with: " ")))
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
                            ? String(appCopy: "Couldn't lift this off its background -- it's here as it came.")
                            : String(appCopy: "Couldn't lift these off their background -- they're here as they came."))
                        : String(appCopy: "One of these kept its background. They're all here -- pick either.")
                }
                if images.isEmpty {
                    notice = String(appCopy: "Mira couldn't make that one -- try other words?")
                }
                drafts = images.map { StickerDraft(prompt: trimmed, data: $0) }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? String(appCopy: "Making a sticker didn't work this time. Try again?")
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
                // No white edge (team decision 2026-10-24): stickers come out
                // without one, and the Outline tile adds it on request.
                // Trimmed to the subject: Vision's cut keeps the whole photo's
                // canvas, which /border used to crop for the outlined variant.
                let cut = StickerTrim.croppedToOpaqueBounds(
                    try await studio.cutout(image: data, target: nil))
                drafts = [StickerDraft(prompt: photo.displayName, data: cut, style: .cutout)]
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? String(appCopy: "That didn't work this time. Try again?")
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
                        notice = String(appCopy: "That didn't work this time. Try again?")
                        return
                    }
                    restyled = mono
                }
                guard drafts.indices.contains(index) else { return }
                drafts[index].push(StickerVariant(data: restyled, style: style))
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? String(appCopy: "That didn't work this time. Try again?")
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

    /// "Add to page" (or a tap on the sticker): the showing sticker hops in
    /// 0.25 s onto a free spot of the page in view, lands selected, and a
    /// toast offers Undo.
    private func add() {
        guard !busy, drafts.indices.contains(page), flight == nil else { return }
        // Saved here, so a write failure is reported next to the sticker.
        guard let fileName = try? imageStore.save(drafts[page].current.data, id: UUID()) else {
            notice = String(appCopy: "That sticker couldn't be saved. Try again?")
            return
        }
        hop(PendingPlacement(prompt: drafts[page].prompt, fileName: fileName, at: landingSpot))
    }

    // MARK: The hop onto the page

    /// The free spot nearest the middle of the card as the canvas will show
    /// it (where it stood, the sheet gone), page points.
    private var landingSpot: CGPoint {
        let card = pageCard
        let visible = CGRect(x: 0, y: scrollMemory.offset,
                             width: MiraNoteConfig.pageWidth, height: card.frame.height / card.scale)
        return StickerSpot.find(in: visible, avoiding: editor.items)
    }

    /// A spot in page points, on screen (global), the page as it stands.
    private func onScreen(_ point: CGPoint) -> CGPoint {
        let card = pageCard
        return CGPoint(x: card.frame.minX + point.x * card.scale,
                       y: card.frame.minY + (point.y - scrollMemory.offset) * card.scale)
    }

    /// The hop's length: a quarter second, quick enough never to wait on.
    private static let hop = 0.25

    /// The sticker leaves the preview along a short arc (across fast, down
    /// late) as the sheet slides away, and arrives 8 % large, which the
    /// canvas settles. A touch during the hop lands it at once.
    private func hop(_ pending: PendingPlacement) {
        guard let image = UIImage(data: drafts[page].current.data) else { return }
        let target = onScreen(pending.at)
        flight = Flight(image: image, x: previewFrame.midX, y: previewFrame.midY,
                        side: min(232, previewFrame.height))
        flightPending = pending
        withAnimation(.easeOut(duration: Self.hop)) {
            flight?.x = target.x
            flight?.side = StickerSpot.side * pageCard.scale * 1.08
        }
        withAnimation(.easeIn(duration: Self.hop)) { flight?.y = target.y }
        Task {
            try? await Task.sleep(for: .seconds(Self.hop))
            land()
        }
    }

    /// Hands the hopping sticker to the canvas, once: when the hop ends, or
    /// at a touch during it.
    private func land() {
        guard let pending = flightPending else { return }
        flightPending = nil
        pendingPlacement = pending
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
