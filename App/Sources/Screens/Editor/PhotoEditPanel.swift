import MiraNoteKit
import SwiftUI

/// The photo editor's working state while a photo is lifted above the
/// scrimmed canvas (handoff screens 27-28): which tile the composer speaks
/// for, the words typed, a running edit, and the compare. Owned by the
/// canvas scene: the stage, the Photo Editing sheet and the composer are
/// three views in three places reading one state.
@MainActor
@Observable
final class PhotoEditController {
    /// The Photo Editing tiles: the design's four, then the existing
    /// filters and frames (decision 2026-10-15).
    enum Tile: String, CaseIterable, Identifiable {
        case ai, outline, cutout, bw, match, warm, film, white, polaroid

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ai: return "AI Editing"
            case .outline: return "Outline"
            case .cutout: return "Cutout"
            case .bw, .match, .warm, .film: return PhotoFilter(rawValue: rawValue)?.label ?? rawValue
            case .white, .polaroid: return PhotoFrame(rawValue: rawValue)?.label ?? rawValue
            }
        }

        /// Filters and frames keep their old identifiers.
        var accessibilityID: String {
            switch self {
            case .bw, .match, .warm, .film: return "photo.filter.\(rawValue)"
            case .white, .polaroid: return "photo.frame.\(rawValue)"
            case .ai, .outline, .cutout: return "photo.tile.\(rawValue)"
            }
        }
    }

    let itemID: CanvasItem.ID
    /// The tile the composer speaks for: AI Editing and Cutout take words;
    /// nil when every edit acts at once and the composer offers Done.
    var wordsFor: Tile?
    /// Outline leaves no lasting mark on the photo's ref, so its tile stays
    /// lit from its run until the next tile.
    private(set) var lastRun: Tile?
    var prompt = ""
    private(set) var working = false
    var notice: String?
    /// A short tap on Compare pins the split view; a hold shows it while held.
    var pinnedCompare = false
    var holdingCompare = false
    private(set) var isFavorite: Bool
    /// The photo as this visit opened it: Cancel puts it back. Edits kept
    /// with Done on an earlier visit are not this visit's to discard.
    let visitStart: ImageRef?

    /// This visit's own undo steps on top of the page's history, and the
    /// page's change count right after the last of them. Any other change
    /// (a text block, a Mira edit between visits) moves the count, and the
    /// floating Undo then steps aside instead of taking that change back.
    private var ownSteps = 0
    private var ownCount: Int?
    /// The running studio call; Cancel stops it, and a result that still
    /// arrives afterwards is dropped.
    private var work: Task<Void, Never>?
    private var cancelled = false

    private let editor: CanvasViewModel
    private let studio: ImageStudioService
    private let onEdited: () -> Void
    private let onClose: () -> Void
    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    init(
        itemID: CanvasItem.ID,
        editor: CanvasViewModel,
        studio: ImageStudioService,
        onEdited: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.editor = editor
        self.studio = studio
        self.onEdited = onEdited
        self.onClose = onClose
        var start: ImageRef?
        if case .image(let ref) = editor.item(itemID)?.content { start = ref }
        visitStart = start
        let file = start?.fileName ?? ""
        isFavorite = favoritesStore.all().contains { $0.fileName == file && !file.isEmpty }
    }

    var comparing: Bool { pinnedCompare || holdingCompare }

    // MARK: This visit's steps

    /// The floating Undo: only while the page's newest step is this visit's.
    var canUndo: Bool { !working && ownSteps > 0 && editor.changeCount == ownCount }

    func undo() {
        guard canUndo else { return }
        editor.undo()
        ownSteps -= 1
        ownCount = editor.changeCount
    }

    /// Runs one of this visit's edits, counting the step it records.
    private func recordOwn(_ edit: () -> Void) {
        let before = editor.changeCount
        edit()
        guard editor.changeCount != before else { return }
        // Something else came between: those older steps are not on top.
        if ownCount != before { ownSteps = 0 }
        ownSteps += 1
        ownCount = editor.changeCount
    }

    /// The header's Cancel: a running AI edit or cutout stops, and its
    /// result, should it still arrive, is dropped.
    func cancelWork() {
        cancelled = true
        work?.cancel()
        work = nil
        working = false
    }

    var currentRef: ImageRef? {
        if case .image(let ref) = editor.item(itemID)?.content { return ref }
        return nil
    }

    func isSelected(_ tile: Tile) -> Bool {
        switch tile {
        case .ai, .cutout: return wordsFor == tile
        case .outline: return wordsFor == nil && lastRun == .outline
        case .bw, .match, .warm, .film: return currentRef?.filterName == tile.rawValue
        case .white, .polaroid: return currentRef?.frameName == tile.rawValue
        }
    }

    func tap(_ tile: Tile) {
        guard !working else { return }
        // A notice narrates ONE action; it must not outlive the next tap.
        notice = nil
        switch tile {
        case .ai, .cutout:
            wordsFor = wordsFor == tile ? nil : tile
        case .outline:
            wordsFor = nil
            runOutline()
        case .bw, .match, .warm, .film:
            wordsFor = nil
            lastRun = tile
            // A second tap takes the filter back off -- one step either way.
            let filter = isSelected(tile) ? "" : tile.rawValue
            recordOwn { editor.setImageFilter(itemID: itemID, to: filter) }
            onEdited()
        case .white, .polaroid:
            wordsFor = nil
            lastRun = tile
            let frame = isSelected(tile) ? "" : tile.rawValue
            recordOwn { editor.setImageFrame(itemID: itemID, to: frame) }
            onEdited()
        }
    }

    // MARK: Composer

    var composerCopy: String {
        switch wordsFor {
        case .ai: return "Tell AI what to change"
        case .cutout: return "Describe cutout target"
        default: return "Undo last edit or hold compare"
        }
    }

    var composerAction: String { wordsFor == nil ? "Done" : "Edit" }

    var composerEnabled: Bool {
        guard !working else { return false }
        if wordsFor == .ai { return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    func runComposer() {
        switch wordsFor {
        case .ai: runAIEdit()
        case .cutout: runCutout()
        default: onClose()
        }
    }

    // MARK: Favorite

    func favorite() {
        guard !isFavorite, let ref = currentRef, !ref.fileName.isEmpty else { return }
        favoritesStore.add(GeneratedSticker(
            prompt: ref.displayName, symbolName: "photo", fileName: ref.fileName, kind: .image
        ))
        isFavorite = true
    }

    // MARK: Studio edits

    private var currentPixels: Data? {
        guard let ref = currentRef else { return nil }
        return imageStore.data(forFileName: ref.fileName)
    }

    /// The white outline around the photo's current pixels, in place.
    private func runOutline() {
        guard let data = currentPixels else {
            notice = "This picture has no stored pixels to outline."
            return
        }
        lastRun = .outline
        run {
            let outlined = try await self.studio.outline(image: data)
            guard !self.cancelled else { return }
            let fileName = try self.imageStore.save(outlined, id: UUID())
            self.recordOwn { self.editor.replaceImageFile(itemID: self.itemID, fileName: fileName) }
            self.onEdited()
        }
    }

    /// "Change the photo with words": new pixels in place. The editor stays
    /// open on the result (screen 28): compare, undo or Done.
    private func runAIEdit() {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        guard let data = currentPixels else {
            notice = "This picture has no stored pixels to change."
            return
        }
        lastRun = .ai
        run {
            let edited = try await self.studio.stylize(image: data, instruction: instruction)
            guard !self.cancelled else { return }
            let fileName = try self.imageStore.save(edited, id: UUID())
            self.recordOwn { self.editor.replaceImageFile(itemID: self.itemID, fileName: fileName) }
            self.onEdited()
            self.prompt = ""
            self.wordsFor = nil
            // New pixels, new sentence: refresh the vision summary.
            if let summary = try? await self.studio.describe(image: edited), !self.cancelled {
                self.editor.setImageSummary(itemID: self.itemID, to: summary)
            }
        }
    }

    /// The subject lifted off its background: the photo becomes a sticker
    /// in place (one undo step back), which ends photo editing. Nothing on
    /// the canvas changes unless the cutout succeeds.
    private func runCutout() {
        guard let ref = currentRef, let data = currentPixels else {
            notice = "This picture has no stored pixels to cut."
            return
        }
        let target = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            let cut = try await self.studio.cutout(image: data, target: target.isEmpty ? nil : target)
            guard !self.cancelled else { return }
            let fileName = try self.imageStore.save(cut, id: UUID())
            self.editor.replaceImageWithSticker(itemID: self.itemID, sticker: GeneratedSticker(
                prompt: target.isEmpty ? ref.displayName : target,
                symbolName: "sparkles",
                fileName: fileName
            ))
            self.onClose()
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !working, !cancelled else { return }
        working = true
        notice = nil
        self.work = Task {
            defer {
                if !cancelled { working = false }
            }
            do {
                try await work()
            } catch {
                guard !cancelled, !(error is CancellationError) else { return }
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}

// MARK: - Stage, sheet, composer

/// Screens 27-28 above the tool bar: the lifted photo with its floating
/// Undo / Compare / Favorite, 30 above the Photo Editing sheet.
struct PhotoEditOverlay: View {
    @Bindable var controller: PhotoEditController
    /// The session's original: what Compare shows as Before.
    let original: ImageRef
    /// Whether the session edited the photo (an older edit undone from the
    /// header is not one to take back here).
    let edited: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 30) {
                Spacer(minLength: 0)
                PhotoEditStage(
                    controller: controller, original: original, edited: edited, width: geo.size.width
                )
                PhotoEditSheet(controller: controller)
            }
        }
    }
}

private struct PhotoEditStage: View {
    @Bindable var controller: PhotoEditController
    let original: ImageRef
    let edited: Bool
    /// The sheet's width: the lifted photo is at most this wide.
    let width: CGFloat

    @GestureState private var holding = false
    @State private var pressBegan: Date?

    private let imageStore = ImageFileStore()

    /// The design's lifted box: 342 x 323 on a 374 pt screen.
    private static let boxAspect: CGFloat = 323.0 / 342.0

    var body: some View {
        let size = photoSize
        // The cluster rides the photo's top-left: 34 in, 23 above, so its
        // lower third overlaps the photo (screen 27).
        ZStack(alignment: .topLeading) {
            photo(size: size)
                .offset(x: (width - size.width) / 2, y: 23)
            cluster
                .offset(x: (width - size.width) / 2 + 34, y: 0)
        }
        .frame(width: width, height: 23 + size.height, alignment: .topLeading)
        .onChange(of: holding) { _, held in
            controller.holdingCompare = held
            if !held { pressBegan = nil }
        }
        // A visible change to the photo ends a comparison -- a filter tapped
        // mid-compare must show, not hide behind the original.
        .onChange(of: controller.currentRef) { old, new in
            if let old, let new, Self.looksEdited(new, from: old) { controller.pinnedCompare = false }
        }
        .onDisappear { controller.holdingCompare = false }
    }

    private var looksEdited: Bool {
        guard edited, let ref = controller.currentRef else { return false }
        return Self.looksEdited(ref, from: original)
    }

    /// What the eye sees -- a vision summary landing mid-session is not an edit.
    static func looksEdited(_ ref: ImageRef, from original: ImageRef) -> Bool {
        ref.fileName != original.fileName || ref.filterName != original.filterName
            || ref.frameName != original.frameName
    }

    // MARK: Photo

    /// Aspect-true inside the design's box, full sheet width at most.
    private var photoSize: CGSize {
        let boxWidth = width
        let boxHeight = (boxWidth * Self.boxAspect).rounded()
        guard let image = uiImage(controller.currentRef), image.size.height > 0 else {
            return CGSize(width: boxWidth, height: boxHeight)
        }
        let aspect = image.size.width / image.size.height
        if aspect >= boxWidth / boxHeight {
            return CGSize(width: boxWidth, height: (boxWidth / aspect).rounded())
        }
        return CGSize(width: (boxHeight * aspect).rounded(), height: boxHeight)
    }

    private func uiImage(_ ref: ImageRef?) -> UIImage? {
        guard let ref else { return nil }
        return CanvasImageCache.image(fileName: ref.fileName, filterName: ref.filterName, store: imageStore)
    }

    @ViewBuilder private func photo(size: CGSize) -> some View {
        let radius = min(66, min(size.width, size.height) * 0.2)
        let shape = RoundedRectangle(cornerRadius: radius)
        ZStack {
            framed(controller.currentRef, size: size, radius: radius)
            if controller.comparing {
                framed(original, size: size, radius: radius)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width / 2)
                    }
                Rectangle()
                    .fill(Palette.onInk)
                    .frame(width: 1, height: size.height)
                    .accessibilityHidden(true)
                compareLabels(size: size)
            }
            if controller.working {
                DotRingSpinner(diameter: min(122, size.height * 0.6))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo.lifted")
    }

    /// The photo with its frame drawn as the canvas draws it, scaled up.
    @ViewBuilder private func framed(_ ref: ImageRef?, size: CGSize, radius: CGFloat) -> some View {
        let pixels = Group {
            if let image = uiImage(ref) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GradientPlaceholder()
            }
        }
        switch PhotoFrame(rawValue: ref?.frameName ?? "") ?? .none {
        case .none:
            pixels
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: radius))
        case .white:
            pixels
                .frame(width: size.width - 20, height: size.height - 20)
                .clipShape(RoundedRectangle(cornerRadius: max(radius - 10, 6)))
                .frame(width: size.width, height: size.height)
                .background(RoundedRectangle(cornerRadius: radius).fill(.white))
        case .polaroid:
            pixels
                .frame(width: size.width - 24, height: size.height - 64)
                .clipped()
                .padding(.bottom, 40)
                .frame(width: size.width, height: size.height)
                .background(Rectangle().fill(.white))
        }
    }

    /// Screen 28: "Before" over the original half, "Current" over the edit,
    /// 42 above the photo's lower edge. On soft paper capsules -- plain
    /// muted text vanished on dark photos.
    private func compareLabels(size: CGSize) -> some View {
        HStack(spacing: 0) {
            label("Before", color: Palette.muted, id: "photo.before")
                .frame(width: size.width / 2)
            label("Current", color: Palette.ink, id: "photo.current")
                .frame(width: size.width / 2)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 34)
    }

    private func label(_ text: String, color: Color, id: String) -> some View {
        Text(text)
            .font(Sans.font(size: 10, weight: 700))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 16)
            .background(Capsule().fill(Color.white.opacity(0.72)))
            .accessibilityIdentifier(id)
    }

    // MARK: Floating cluster

    private var cluster: some View {
        HStack(spacing: 9.5) {
            Button(action: controller.undo) {
                FloatingCircle { FloatingGlyph.undo() }
            }
            .buttonStyle(.plain)
            // Only this visit's own steps: never something newer on the page.
            .disabled(!controller.canUndo)
            .accessibilityLabel("Undo last edit")
            .accessibilityIdentifier("photo.undo")

            FloatingCircle(active: controller.comparing) { FloatingGlyph.compare }
                // Gesture state, not onEnded alone: a hold the system
                // cancels (a call, Control Center) still lets go.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($holding) { _, state, _ in state = true }
                        .onChanged { _ in if pressBegan == nil { pressBegan = .now } }
                        .onEnded { _ in
                            // A short tap pins the split; a hold only shows it.
                            if let began = pressBegan, Date.now.timeIntervalSince(began) < 0.3 {
                                controller.pinnedCompare.toggle()
                            }
                            pressBegan = nil
                        },
                    including: looksEdited ? .all : .none
                )
                .opacity(looksEdited ? 1 : 0.45)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Compare with the original")
                // VoiceOver cannot hold: activating toggles the comparison,
                // and the value says what is showing.
                .accessibilityAction { if looksEdited { controller.pinnedCompare.toggle() } }
                .accessibilityValue(controller.comparing ? "Showing before and current" : "Showing your edit")
                .accessibilityIdentifier("photo.compare")

            Button(action: controller.favorite) {
                FloatingCircle { FloatingGlyph.favorite(saved: controller.isFavorite) }
            }
            .buttonStyle(.plain)
            .disabled(controller.isFavorite)
            .accessibilityLabel(controller.isFavorite ? "In Favorites" : "Add to Favorites")
            .accessibilityIdentifier("photo.favorite")
        }
    }
}

/// Screen 27's "Photo Editing" sheet: one scrolling row of 62 x 48 tiles.
private struct PhotoEditSheet: View {
    @Bindable var controller: PhotoEditController

    var body: some View {
        GlassSheet(title: "Photo Editing", border: Color(hex: 0xEEEEE9)) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(PhotoEditController.Tile.allCases) { tile in
                            EditTile(label: tile.label, selected: controller.isSelected(tile)) {
                                controller.tap(tile)
                            }
                            .disabled(controller.working)
                            .accessibilityIdentifier(tile.accessibilityID)
                        }
                    }
                    .padding(.horizontal, 23)
                }
                .padding(.horizontal, -21)

                if let notice = controller.notice {
                    Text(notice)
                        .font(.miraComposer)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("photo.notice")
                }
            }
        }
    }
}

/// The composer while a photo is lifted: its copy and action follow the tile.
struct PhotoEditComposer: View {
    @Bindable var controller: PhotoEditController

    var body: some View {
        ToolComposer(
            placeholder: controller.composerCopy,
            text: controller.wordsFor == nil ? nil : $controller.prompt,
            action: controller.composerAction,
            actionEnabled: controller.composerEnabled,
            fieldID: "photo.prompt",
            actionID: "photo.composer.action",
            onAction: controller.runComposer
        )
    }
}
