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
    /// The words the showing stickers were made from (sticker Add option B:
    /// the composer adds them until new words are typed).
    @State private var madeFrom = ""
    /// Option A3: where a sticker dragged out of the sheet is, and the page
    /// row it can land on (both global).
    @State private var dragPoint: CGPoint?
    @State private var pageRow: CGRect = .zero
    @State private var previewFrame: CGRect = .zero
    /// While typing, the sheet folds to its collapsed height: the keyboard
    /// leaves no room for 430 above the composer.
    @FocusState private var promptFocused: Bool

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        EditorScaffold(
            leading: "Cancel",
            // Round 2 of sticker Add: the sheet's own Add replaces this one
            // while a made sticker shows (or is on its way).
            trailing: UIVariant.stickerAdd.hidesHeaderAdd && (generating || !drafts.isEmpty) ? nil : "Add",
            onLeading: actions.leading,
            onTrailing: add,
            // The panel records no step of its own (presets and favorites
            // leave it as they place; a made sticker has its own undo): the
            // header Undo has nothing here, never a change under the scrim.
            onUndo: {},
            undoEnabled: false,
            // A sticker dragged out (option A3) shows the page it lands on.
            scrimmed: dragPoint == nil,
            onScrimTap: {
                // A tap on the page goes back to it -- except while a
                // sticker is being made or waits to be added: it took
                // seconds and real credits, and leaving would drop it.
                guard !placingWouldDropWork else { return }
                actions.leading()
            }
        ) {
            // The page the sticker will land on, read-only under the scrim.
            PagePreview(memory: editor.memory) {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pageRow = $0 }
        } sheet: {
            sheet
                .frame(height: sheetHeight)
                .animation(.spring(response: 0.35), value: sheetHeight)
                // Out of the way while a sticker is dragged onto the page.
                .opacity(dragPoint == nil ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: dragPoint == nil)
        } bottom: {
            InputModeBar(active: .sticker, onSelect: { mode in
                // Another tool leaves the panel: same rule as the presets.
                guard mode == .sticker || !placingWouldDropWork else {
                    notice = "Add the sticker you made first, or Cancel to let it go."
                    return
                }
                actions.selectMode(mode)
            })
            // Sticker Add option B: with a made sticker showing and no new
            // words typed, the composer's action adds it; Make again sits
            // beside it. New words bring Generate back.
            ToolComposer(
                placeholder: "Ask mira to generate a sticker",
                text: $prompt,
                action: composerAdds ? "Add" : "Generate",
                actionWidth: composerAdds ? 52 : 74,
                actionEnabled: composerAdds ? !busy : canGenerate,
                fieldID: "sticker.prompt",
                actionID: composerAdds ? "sticker.composer.add" : "sticker.generate.run",
                focus: $promptFocused,
                secondary: composerAdds ? ComposerSecondary(
                    symbol: "arrow.clockwise", label: "Make again", id: "sticker.regenerate",
                    enabled: !busy, action: generate
                ) : nil,
                onAction: composerAdds ? add : generate
            )
            .animation(.easeOut(duration: 0.2), value: composerAdds)
        }
        .overlay {
            GeometryReader { geo in
                draggedSticker(origin: geo.frame(in: .global).origin)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // Entries whose image file is gone or degenerate would render as
            // blank squares.
            favorites = favoritesStore.prunedRaisingSmall(images: imageStore)
        }
        #if DEBUG
        // -STICKER_DRAG_POSE x,y: holds a drag there once a sticker shows,
        // for a screenshot of the mid-drag state (XCUITest cannot pause a
        // finger mid-drag).
        .onChange(of: drafts.count) {
            guard let pose = UserDefaults.standard.string(forKey: "STICKER_DRAG_POSE")?
                .split(separator: ",").compactMap({ Double($0) }), pose.count == 2, !drafts.isEmpty else { return }
            dragPoint = CGPoint(x: pose[0], y: pose[1])
        }
        #endif
        #if DEBUG
        .background(DebugStateProbe {
            ["scene": "sticker", "listening": [String: Bool](), "busy": busy, "drafts": drafts.count,
             "undoDepth": editor.undoDepth, "writing": editor.editingTextItemID?.uuidString ?? ""]
        })
        #endif
    }

    private var busy: Bool { generating || styling }

    /// Sticker Add option B: the composer adds the showing sticker.
    private var composerAdds: Bool {
        UIVariant.stickerAdd == .b && !drafts.isEmpty
            && prompt.trimmingCharacters(in: .whitespacesAndNewlines) == madeFrom
    }

    /// A favorite or preset tap places it and leaves the panel, which would
    /// drop a sticker being made or waiting to be added -- it took seconds
    /// and real credits (#93).
    private var placingWouldDropWork: Bool { busy || !drafts.isEmpty }

    /// Collapsed 147 at rest (screen 30); 430 while making or showing a
    /// sticker (32-33); 420 for a full grid (34-35).
    private var sheetHeight: CGFloat {
        if promptFocused { return 147 }
        switch tab {
        // Sticker Add options grow by their pill, hint line, or both.
        case .make: return showsWork ? 430 + addRoom : 147
        case .favorites: return favorites.isEmpty ? 147 : 420
        case .set: return 420
        }
    }

    private var addRoom: CGFloat {
        switch UIVariant.stickerAdd {
        case .current, .b: return 0
        case .c: return 36
        case .a, .a1, .a2: return 70
        case .a3: return 96
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
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { previewFrame = $0 }
                addAffordance
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

            // Option A2 moves Favorite beside "Add to page".
            if UIVariant.stickerAdd != .a2 {
                Button(action: favoriteCurrent) {
                    FloatingCircle { FloatingGlyph.favorite(saved: draft?.current.favorite ?? false) }
                }
                .disabled(busy || draft == nil || (draft?.current.favorite ?? false))
                .accessibilityLabel("Add to Favorites")
                .accessibilityIdentifier("sticker.favorite")
            }
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
                        // Sticker Add option C: the "+" on the sticker's
                        // own corner (the fitted image, not the frame).
                        .overlay(alignment: .bottomTrailing) {
                            if UIVariant.stickerAdd == .c, !busy {
                                addBadge.offset(x: -4, y: -4)
                            }
                        }
                } else {
                    Palette.cardFill
                }
            }
            .frame(maxWidth: 232, maxHeight: 232)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(draft.prompt)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("sticker.result.\(index)")
            // Sticker Add options A and C: the sticker itself adds.
            .onTapGesture { if previewAdds { add() } }
            .gesture(UIVariant.stickerAdd == .a3 && !busy ? dragOut : nil)
            .opacity(dragPoint != nil && index == page ? 0.3 : 1)
            .accessibilityAction(named: "Add to page") { if previewAdds { add() } }
            if styling && index == page {
                DotRingSpinner(diameter: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Add within thumb reach (owner, 2026-10-19)

    private var previewAdds: Bool { UIVariant.stickerAdd.previewAdds }

    /// Under the made sticker: the A options' "Add to page" (A2 with its
    /// Favorite beside it, A3 with the drag hint above), option C's
    /// one-line hint. Today, and option B, nothing (B adds from the
    /// composer).
    @ViewBuilder private var addAffordance: some View {
        let option = UIVariant.stickerAdd
        if option == .c {
            Text("Tap the sticker to add it")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)
        } else if option.addPill {
            VStack(spacing: 8) {
                if option == .a3 {
                    Text("Drag onto the page or tap Add")
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("sticker.dragHint")
                }
                HStack(spacing: 10) {
                    addPill
                    if option == .a2 { favoriteButton }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    // MARK: Drag onto the page (option A3)

    /// A short press lifts the sticker (a swipe still pages between made
    /// ones); it follows the finger and lands where it is let go over the
    /// page. Anywhere else it goes back into the sheet.
    private var dragOut: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            // Inside the preview's TabView pages a drag reports locations
            // in the page's own space, whatever space is asked for: the
            // sticker's centre is the preview's (read outside the TabView)
            // moved by the finger's translation.
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value { dragPoint = lifted(by: drag.translation) }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else {
                    dragPoint = nil
                    return
                }
                drop(at: lifted(by: drag.translation))
            }
    }

    private func lifted(by translation: CGSize) -> CGPoint {
        CGPoint(x: previewFrame.midX + translation.width, y: previewFrame.midY + translation.height)
    }

    /// The card within the page row, and page points per screen point.
    private var pageCard: (frame: CGRect, scale: CGFloat) {
        let inset = UIVariant.canvasSideInset ?? (pageRow.width - MiraNoteConfig.pageWidth) / 2
        let card = pageRow.insetBy(dx: inset, dy: 0)
        return (card, card.width / MiraNoteConfig.pageWidth)
    }

    private func drop(at point: CGPoint) {
        dragPoint = nil
        let card = pageCard
        guard card.frame.contains(point), drafts.indices.contains(page),
              let fileName = try? imageStore.save(drafts[page].current.data, id: UUID()) else { return }
        // The preview shows the page from its top.
        let onPage = CGPoint(x: (point.x - card.frame.minX) / card.scale,
                             y: (point.y - card.frame.minY) / card.scale)
        let id = editor.addSticker(
            GeneratedSticker(prompt: drafts[page].prompt, symbolName: "sparkles", fileName: fileName),
            at: onPage
        )
        editor.select(id)
        actions.leading()
    }

    /// The lifted sticker, over everything, at the page's own sticker size,
    /// with a word on what letting go does. `origin` is the overlay's
    /// global origin.
    @ViewBuilder private func draggedSticker(origin: CGPoint) -> some View {
        if let dragPoint, drafts.indices.contains(page),
           let image = UIImage(data: drafts[page].current.data) {
            let overPage = pageCard.frame.contains(dragPoint)
            let side = 88 * pageCard.scale
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // The 88 pt a placed sticker takes (`addSticker`).
                    .frame(width: side, height: side)
                    .scaleEffect(1.06)
                    .shadow(color: Palette.ink.opacity(0.28), radius: 14, y: 10)
                Text(overPage ? "Let go to place it" : "Drag onto the page")
                    .font(.miraChip)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Palette.ink.opacity(0.88)))
                    .fixedSize()
                    .offset(y: -side / 2 - 26)
            }
            .position(x: dragPoint.x - origin.x, y: dragPoint.y - origin.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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

    /// Option A2: Favorite as the pill's 46 pt paper companion (the floating
    /// favorite circle goes); a filled star once saved.
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
        .accessibilityLabel(saved ? "In Favorites" : "Add to Favorites")
        .accessibilityIdentifier("sticker.favorite")
    }

    /// Option C's 44 pt ink "+" on the preview's corner, ringed in paper so
    /// it reads over any sticker.
    private var addBadge: some View {
        Button(action: add) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.onInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.ink))
                .overlay(Circle().strokeBorder(Palette.paper, lineWidth: 3))
                .shadow(color: Palette.ink.opacity(0.22), radius: 8, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to page")
        .accessibilityIdentifier("sticker.addBadge")
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
                madeFrom = trimmed
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
                madeFrom = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
