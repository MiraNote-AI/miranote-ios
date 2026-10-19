import AVFoundation
import MiraNoteKit
import SwiftUI

/// Where the canvas page stands (page points from its top), kept by the
/// editor flow across the Sticker panel's round trip. A plain box: written
/// on every scroll frame without re-rendering anything.
final class CanvasScrollMemory {
    var offset: CGFloat = 0
}

/// The v2.1 infinite canvas: a vertically scrolling page of freely placed
/// elements. Gesture grammar ("press to drag, long-press for menu"):
/// press-and-drag moves any element directly (and selects it), tap selects,
/// tap on empty paper deselects, dragging empty paper scrolls the page,
/// long-press opens the context menu, dropping a dragged element below the
/// canvas deletes it (the menu's Delete is the other path), corner handles
/// resize, and two fingers rotate.
struct CanvasBoardView: View {
    @Bindable var editor: CanvasViewModel
    var soundStore = SoundFileStore()
    var textFocus: FocusState<CanvasItem.ID?>.Binding
    /// Elements Mira is currently changing: they breathe and ignore touches
    /// (lock the element, never the screen).
    var workingItemIDs: Set<CanvasItem.ID> = []
    /// Long-press "Edit photo" (images with stored pixels only).
    var onEditImage: (CanvasItem.ID) -> Void = { _ in }
    var onEditSticker: (CanvasItem.ID) -> Void = { _ in }
    /// A tap on empty paper (not while placing): lets the scene fold
    /// away a tool that is open but idle.
    var onPaperTap: () -> Void = {}
    /// Long-press "Favorite": saves the image/sticker to the Favorites shelf.
    var onFavorite: (CanvasItem) -> Void = { _ in }
    /// Non-nil while dictated words are on their way to the block being
    /// written: a tap or drag that would end the writing hands over what it
    /// does next, and the scene ends the writing (as Done, waiting for the
    /// words) before doing it.
    var onEndWritingThen: ((@escaping () -> Void) -> Void)?
    /// Set when an edit panel closes: the edited element scrolls into view
    /// once the panel has given its room back, then this clears.
    var revealItem: Binding<CanvasItem.ID?> = .constant(nil)
    /// Where an in-flight move stands against the delete zone; nil when
    /// nothing is being moved.
    @Binding var dropToDelete: DropToDelete?
    /// The element being moved, for the scene to draw above the dock
    /// (screen 22): the board's own copy hides, so the drag is never cut at
    /// the card's edge. Nil when nothing is being moved.
    var lift = LiftTracker()
    /// While Voice records: where the take will land, in page points.
    var pendingSoundMarker: CGPoint?
    /// While writing: the top of the text tools (or the color sheet) over
    /// the keyboard, global; the block being written stays above it.
    var textToolsTop: CGFloat?
    /// A sticker the Sticker panel's Add just placed: it settles, and the
    /// toast offers Undo.
    var landing: Landing?
    /// Where the page stands, kept across the Sticker panel's round trip.
    var scrollMemory = CanvasScrollMemory()

    @State private var player = SoundPlayer()
    /// The visible canvas, in global coordinates: releasing below it deletes.
    @State private var visibleFrame: CGRect = .zero
    // Transient gesture values: @GestureState resets automatically when a
    // gesture is CANCELLED (context menu, incoming call, backgrounding), so
    // no stale origin can teleport an element or skip an undo snapshot. The
    // model commits once, on gesture end.
    @GestureState private var activeMove: ActiveMove?
    @GestureState private var activeResize: ActiveResize?
    @GestureState private var activeRotation: ActiveRotation?
    @State private var noteDraft = ""
    @State private var noteEditingItem: CanvasItem.ID?
    /// Where the reveal anchor sits while a reveal is in flight.
    @State private var revealFrame: CGRect?
    /// The spot of the block being written to scroll into view, and the
    /// block's frame on screen (global).
    @State private var editAnchor: CGPoint?
    @State private var writtenFrame: CGRect?
    /// Where the page stood before the writing scrolled it; while the
    /// scroll back is in flight, the spot to scroll the page's top to.
    @State private var restoreAnchor: CGPoint?
    @State private var scrollMemo = ScrollMemo()
    /// The page is back where it stood (`scrollMemory`): from here on its
    /// scroll is the one to keep.
    @State private var resumed = false
    @State private var toast: Toast?
    @State private var toastDismiss: Task<Void, Never>?
    /// Screen points per page point: the card fills the screen less its
    /// insets (the visible frame is the card's row, insets included).
    private var pageScale: CGFloat {
        let card = visibleFrame.width - 2 * Metrics.canvasInset
        return card > 0 ? card / MiraNoteConfig.pageWidth : 1
    }

    /// Bottom-edge receipts; deleted and added carry the one-tap Undo, good
    /// while that change is still the page's newest (`changeCount`).
    enum Toast {
        case deleted(changeCount: Int)
        case favorited
        /// The Sticker panel's Add just placed a sticker.
        case added(changeCount: Int)

        var isAdded: Bool {
            if case .added = self { return true }
            return false
        }
    }

    private let minBoardHeight: CGFloat = 620
    private static let revealAnchorID = "canvas.revealAnchor"
    private static let editAnchorID = "canvas.editAnchor"
    private static let restoreAnchorID = "canvas.restoreAnchor"
    private static let scrollSpace = "canvas.scroll"

    /// The page's scroll offset, kept outside SwiftUI's state so reading it
    /// on every scroll frame re-renders nothing.
    final class ScrollMemo {
        var offset: CGFloat = 0
        var beforeWriting: CGFloat = 0
        var cardHeight: CGFloat = 0
        var scrolledForWriting = false
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // The page is a fixed 360 pt column -- the same page on
                // every phone, and the same as its export -- scaled up to
                // fill the card.
                board
                    .scaleEffect(pageScale, anchor: .topLeading)
                    .frame(
                        width: MiraNoteConfig.pageWidth * pageScale,
                        height: boardHeight * pageScale,
                        alignment: .topLeading
                    )
                    // Read on every scroll frame into a plain box: no
                    // re-render while the page scrolls.
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(Self.scrollSpace)).minY
                    } action: {
                        scrollMemo.offset = -$0
                        if resumed { scrollMemory.offset = max(0, -$0 / pageScale) }
                    }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onAppear { returnToKeptScroll(proxy) }
            // The card holds still; the page scrolls inside it.
            .canvasCard()
            // The page keeps its full height under the keyboard while
            // writing: the block being written scrolls clear of the keyboard
            // and the text chrome over the page's lower part -- when it
            // opens, when it grows, when the tools move.
            // Not on the user's own scroll, which moves the block's frame
            // without changing which block it is or its height.
            .onChange(of: writtenKey) { keepWrittenBlockClear(proxy) }
            .onChange(of: textToolsTop) { keepWrittenBlockClear(proxy) }
            .onChange(of: editor.editingTextItemID) { old, id in
                if old == nil, id != nil {
                    scrollMemo.beforeWriting = scrollMemo.offset
                    scrollMemo.cardHeight = visibleFrame.height
                }
                if id == nil {
                    // The flag is cleared only here: the written block's
                    // first frame can land (and set it) before this handler
                    // sees the session start.
                    if scrollMemo.scrolledForWriting { scrollBackAfterWriting(proxy, written: writtenFrame) }
                    scrollMemo.scrolledForWriting = false
                    writtenFrame = nil
                    editAnchor = nil
                }
            }
            .onChange(of: revealItem.wrappedValue) { _, id in
                guard let id, let item = editor.item(id) else { return }
                revealFrame = CGRect(
                    x: item.position.x - item.size.width / 2,
                    y: item.position.y - item.size.height / 2,
                    width: item.size.width,
                    height: item.size.height
                )
                // Wait out the panel's collapse (and the keyboard's) so the
                // scroll centres the element in the grown viewport.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.revealAnchorID, anchor: .center)
                    }
                    revealItem.wrappedValue = nil
                }
            }
        }
        // Dragging an element moves and selects it, which disables the page
        // scroll; dragging empty paper scrolls. While editing text there is
        // no move gesture, so the page scrolls there instead.
        .scrollDisabled(editor.selectedItemID != nil && editor.editingTextItemID == nil && restoreAnchor == nil)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { visibleFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in visibleFrame = frame }
            }
        )
        // Derived from the @GestureState, so a cancelled drag clears the
        // zone too.
        .onChange(of: dropPhase) { _, phase in
            dropToDelete = phase
            if phase == nil { lift.lifted = nil }
        }
        .onChange(of: landing, initial: true) { _, landing in
            if landing != nil { show(toast: .added(changeCount: editor.changeCount)) }
        }
        // A take that leaves the page (Revert, undo, delete) stops playing.
        .onChange(of: editor.changeCount) {
            guard let playing = player.playingID,
                  !editor.items.contains(where: { clipID(of: $0) == playing }) else { return }
            player.stop()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                toastView(toast)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Sound note", isPresented: noteAlertShown) {
            TextField("What is this sound?", text: $noteDraft)
            Button("Cancel", role: .cancel) { noteEditingItem = nil }
            Button("Save") {
                if let id = noteEditingItem {
                    editor.setSoundNote(itemID: id, to: noteDraft)
                }
                noteEditingItem = nil
            }
        } message: {
            Text("A short reminder of what this recording holds.")
        }
    }

    /// While words are written the page goes under the dim glass scrim
    /// (screens 11-20): everything but the edited block blurs and dims.
    private var writing: Bool { editor.editingTextItemID != nil }

    /// The block being written and its height: what keeps it clear of the
    /// text tools when it changes (its first frame, its growth).
    private var writtenKey: WrittenKey? {
        writtenFrame.map { WrittenKey(id: editor.editingTextItemID, height: $0.height) }
    }

    private struct WrittenKey: Equatable {
        let id: CanvasItem.ID?
        let height: CGFloat
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            // A blank page is just the page (handoff screen 04): the tools
            // and the composer below are the invitation.
            paper
                .blur(radius: writing ? 4 : 0)
            if writing {
                // Taps fall through to the paper, which ends editing.
                Rectangle()
                    .fill(Palette.scrim)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(1)
                    .accessibilityElement()
                    .accessibilityLabel("Writing")
                    .accessibilityIdentifier("text.scrim")
            }
            ForEach(editor.orderedItems) { item in
                let edited = editor.editingTextItemID == item.id
                element(item)
                    .blur(radius: writing && !edited ? 4 : 0)
                    .zIndex(edited ? 2 : 0)
            }
            if let pendingSoundMarker {
                PendingSoundMarker()
                    .position(pendingSoundMarker)
            }
            if let revealFrame {
                // Elements are placed with .position, which stretches their
                // frame to the whole board, so scrollTo(item.id) cannot find
                // them. This clear twin sits exactly where the element is.
                Color.clear
                    .frame(width: revealFrame.width, height: revealFrame.height)
                    .alignmentGuide(.leading) { _ in -revealFrame.minX }
                    .alignmentGuide(.top) { _ in -revealFrame.minY }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(Self.revealAnchorID)
            }
            if let editAnchor {
                // Same trick for the block being written: a 1 pt twin at
                // the spot that must come into view.
                Color.clear
                    .frame(width: 1, height: 1)
                    .alignmentGuide(.leading) { _ in -editAnchor.x }
                    .alignmentGuide(.top) { _ in -editAnchor.y }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(Self.editAnchorID)
            }
            if let restoreAnchor {
                Color.clear
                    .frame(width: 1, height: 1)
                    .alignmentGuide(.leading) { _ in -restoreAnchor.x }
                    .alignmentGuide(.top) { _ in -restoreAnchor.y }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(Self.restoreAnchorID)
            }
        }
        .animation(.easeOut(duration: 0.2), value: writing)
        .frame(width: MiraNoteConfig.pageWidth, height: boardHeight)
        // No identifier on the container: SwiftUI cascades a parent
        // accessibilityIdentifier onto contained elements, masking child
        // ids like canvas.textEditor.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { editor.canvasWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        editor.canvasWidth = width
                    }
            }
        )
    }

    /// At least the card's own height, so the page always fills the card;
    /// while writing, a card's height below the content, so the block being
    /// written can always scroll up clear of the keyboard and its tools.
    private var boardHeight: CGFloat {
        let cardHeight = visibleFrame.height / pageScale
        return max(minBoardHeight, cardHeight,
                   editor.contentBottom + (writing ? max(240, cardHeight) : 240))
    }

    /// Keeps the block being written between the card's top and the text
    /// tools over the keyboard (owner, TestFlight 1.0(5): the tools covered
    /// it): its top 16 below the card's top when it fits, else its bottom
    /// just above the tools, where the words are typed.
    private func keepWrittenBlockClear(_ proxy: ScrollViewProxy) {
        guard let id = editor.editingTextItemID, let item = editor.item(id), let shown = writtenFrame,
              let toolsTop = textToolsTop, visibleFrame.height > 0 else { return }
        let bandTop = visibleFrame.minY + 8, bandBottom = toolsTop - 8
        guard shown.minY < bandTop - 0.5 || shown.maxY > bandBottom + 0.5 else { return }
        let top = item.position.y - item.size.height / 2
        // The band is screen points; the block's height is the page's, shown
        // scaled.
        let fits = item.size.height * pageScale <= bandBottom - bandTop
        editAnchor = CGPoint(x: item.position.x, y: fits ? top - 16 : top + item.size.height + 8)
        let anchorY = fits ? 0 : min(1, max(0, (toolsTop - visibleFrame.minY) / visibleFrame.height))
        scrollMemo.scrolledForWriting = true
        // Once the twin is laid out and the page has grown its room below
        // (writing has just begun): a scroll before that clamps short.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.editAnchorID, anchor: UnitPoint(x: 0.5, y: anchorY))
            }
        }
    }

    /// Owner's lead: once the writing ends, a page it scrolled up goes back
    /// to where it stood before the writing began (the block may stay
    /// selected).
    private func scrollBackAfterWriting(_ proxy: ScrollViewProxy, written shown: CGRect?) {
        scrollMemo.scrolledForWriting = false
        var target = scrollMemo.beforeWriting
        // A new block placed below the fold would vanish (and, still
        // selected, hold the page still): go back only as far as keeps its
        // bottom, as drawn, in the card -- the card as it stood before the
        // writing, not as the keyboard still squeezes it now.
        if let shown {
            let bottom = shown.maxY - visibleFrame.minY + scrollMemo.offset + 16
            target = min(scrollMemo.offset, max(target, bottom - scrollMemo.cardHeight))
        }
        // The offsets are screen points; the anchor sits on the page, which
        // the card shows scaled.
        restoreAnchor = CGPoint(x: MiraNoteConfig.pageWidth / 2, y: max(0, target) / pageScale)
        // Once the keyboard is down and the page has given back the room
        // it grew for the writing (its 0.2 s shrink in flight cut the
        // scroll 50 pt short).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if editor.editingTextItemID == nil {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.restoreAnchorID, anchor: UnitPoint(x: 0.5, y: 0))
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            restoreAnchor = nil
        }
    }

    /// The page itself -- its backdrop stretches with the content, so the
    /// background never "runs out".
    private var paper: some View {
        PageBackdrop(memory: editor.memory)
            .onTapGesture {
                if let onEndWritingThen {
                    onEndWritingThen {
                        editor.select(nil)
                        onPaperTap()
                    }
                } else {
                    editor.endEditingText()
                    editor.select(nil)
                    onPaperTap()
                    textFocus.wrappedValue = nil
                }
            }
    }

    // MARK: Elements

    @ViewBuilder private func element(_ item: CanvasItem) -> some View {
        let isSelected = editor.selectedItemID == item.id
        let isEditing = editor.editingTextItemID == item.id
        let geometry = effectiveGeometry(item)
        let isLifted = activeMove?.itemID == item.id

        CanvasElementView(
            item: item,
            isSelected: isSelected,
            isEditingText: isEditing,
            isPlaying: player.playingID == clipID(of: item),
            text: textBinding(item),
            textFocus: textFocus,
            onTogglePlay: { togglePlay(item) },
            onEditNote: { beginNoteEdit(item) }
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .overlay {
            if isSelected && !isEditing {
                handles(for: item, size: geometry.size)
            }
        }
        .background { if isLifted { liftReporter(item, rotation: geometry.rotation) } }
        .background {
            if isEditing {
                Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    writtenFrame = $0
                }
            }
        }
        // Drawn by the scene while lifted; the gesture stays with this view.
        .opacity(isLifted ? 0 : 1)
        .rotationEffect(.degrees(geometry.rotation))
        .position(geometry.position)
        .id(item.id)
        .onTapGesture { handleTap(item, isSelected: isSelected) }
        .gesture(isEditing ? nil : moveGesture(item))
        .simultaneousGesture(isSelected ? rotateGesture(item) : nil)
        .contextMenu { contextMenu(for: item) }
        .modifier(BreathingLock(active: workingItemIDs.contains(item.id)))
        .modifier(Settle(active: landing?.itemID == item.id))
    }

    /// The moving element's box on screen, translation included: the scene
    /// draws the lifted copy exactly there. Read inside the element's tilt,
    /// the global frame is the tilted bounding box: the copy takes the
    /// element's own size (`geo.size`) around its centre.
    private func liftReporter(_ item: CanvasItem, rotation: Double) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { lift(item, frame: geo.frame(in: .global), size: geo.size, rotation: rotation) }
                .onChange(of: geo.frame(in: .global)) { _, frame in
                    lift(item, frame: frame, size: geo.size, rotation: rotation)
                }
        }
    }

    private func lift(_ item: CanvasItem, frame: CGRect, size: CGSize, rotation: Double) {
        // The drop's own frame change can land after the move ended: never
        // bring the copy back then.
        guard let activeMove, activeMove.itemID == item.id else { return }
        lift.lifted = LiftedElement(item: item, measured: frame, size: size, rotation: rotation,
                                    finger: activeMove.location)
    }

    /// Model geometry plus any in-flight gesture translation for this item.
    /// The model itself only changes when a gesture ends, so a cancelled
    /// gesture reverts visually for free.
    private func effectiveGeometry(_ item: CanvasItem) -> ElementGeometry {
        var position = item.position
        var size = item.size
        var rotation = item.rotation
        if let move = activeMove, move.itemID == item.id {
            position.x += move.translation.width / pageScale
            position.y += move.translation.height / pageScale
        }
        if let resize = activeResize, resize.itemID == item.id {
            size.width = max(44, size.width + resize.corner.sign.x * resize.translation.width)
            size.height = max(36, size.height + resize.corner.sign.y * resize.translation.height)
            position.x += resize.translation.width / 2
            position.y += resize.translation.height / 2
        }
        if let spin = activeRotation, spin.itemID == item.id {
            rotation += spin.degrees
        }
        return ElementGeometry(position: position, size: size, rotation: rotation)
    }

    private func textBinding(_ item: CanvasItem) -> Binding<String> {
        Binding(
            get: {
                if case .text(let block) = editor.item(item.id)?.content { return block.text }
                return ""
            },
            set: { newText in
                editor.setText(itemID: item.id, to: newText)
                autosize(item.id, text: newText)
            }
        )
    }

}

// MARK: - Gestures, menu, toast, sound

extension CanvasBoardView {
    // MARK: Kept scroll

    /// Back from the Sticker panel the page returns to where it stood, so
    /// what was added while looking further down lands in view.
    private func returnToKeptScroll(_ proxy: ScrollViewProxy) {
        let kept = scrollMemory.offset
        guard kept > 0 else {
            resumed = true
            return
        }
        restoreAnchor = CGPoint(x: MiraNoteConfig.pageWidth / 2, y: kept)
        Task { @MainActor in
            // Once the card has measured itself and the board its height.
            try? await Task.sleep(for: .milliseconds(60))
            proxy.scrollTo(Self.restoreAnchorID, anchor: UnitPoint(x: 0.5, y: 0))
            // The anchor holds the scroll open (a selected element -- the
            // sticker just added -- disables it) until the scroll has run.
            try? await Task.sleep(for: .milliseconds(300))
            restoreAnchor = nil
            resumed = true
        }
    }

    // MARK: Gestures

    private func handleTap(_ item: CanvasItem, isSelected: Bool) {
        if !isSelected {
            let select = {
                editor.select(item.id)
                // An unselected marker reads "tap to play" (screen 09): the
                // tap that selects it also plays it.
                if case .sound = item.content { togglePlay(item) }
            }
            if let onEndWritingThen { onEndWritingThen(select) } else { select() }
            return
        }
        if case .text = item.content {
            editor.startEditingText(item.id)
            textFocus.wrappedValue = item.id
        }
    }

    private var dropPhase: DropToDelete? {
        guard let activeMove else { return nil }
        return isOverDeleteZone(activeMove.location) ? .armed : .dragging
    }

    /// Past the canvas edge by a margin: a drop aimed at the page's last
    /// line must not delete. Never while words are being written: the
    /// keyboard is up over the zone then (a drag while dictated words are
    /// on their way keeps the session open until they land), and a drop
    /// must not delete unseen. CanvasScene lowers the Mira prompt's
    /// keyboard when a move starts.
    private func isOverDeleteZone(_ location: CGPoint) -> Bool {
        editor.editingTextItemID == nil && location.y > visibleFrame.maxY + 24
    }

    private func moveGesture(_ item: CanvasItem) -> some Gesture {
        // Global space: the finger is tracked past the canvas edge, into
        // the delete zone. Translation is the same in either space.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in
                // Once per drag: selecting again on every frame re-renders
                // everything that reads the selection, frame after frame.
                guard editor.selectedItemID != item.id || editor.editingTextItemID != nil else { return }
                if let onEndWritingThen {
                    onEndWritingThen { editor.select(item.id) }
                } else {
                    editor.select(item.id)
                }
            }
            .updating($activeMove) { value, state, _ in
                state = ActiveMove(itemID: item.id, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                if isOverDeleteZone(value.location) {
                    deleteWithToast(item.id)
                    return
                }
                editor.beginChange()
                editor.move(itemID: item.id, to: CGPoint(
                    x: item.position.x + value.translation.width / pageScale,
                    y: item.position.y + value.translation.height / pageScale
                ))
            }
    }

    private func rotateGesture(_ item: CanvasItem) -> some Gesture {
        RotateGesture()
            .updating($activeRotation) { value, state, _ in
                state = ActiveRotation(itemID: item.id, degrees: value.rotation.degrees)
            }
            .onEnded { value in
                editor.beginChange()
                editor.rotate(itemID: item.id, degrees: item.rotation + value.rotation.degrees)
            }
    }

    /// The arrange-state frame (handoff screen 21): a 1 pt dashed #263521
    /// r16 frame 6 outside the element -- or, on an unframed photo, the 3 pt
    /// ink border along its r18 edge (screen 29) -- with 10 pt corner
    /// handles that hit-test at 44. Corner drags resize around the opposite
    /// corner; deltas are applied in unrotated space (a deliberate
    /// simplification -- scrapbook tilts stay small).
    private func handles(for item: CanvasItem, size: CGSize) -> some View {
        let line = Color(hex: 0x263521)
        var photoBorder = false
        if case .image(let ref) = item.content { photoBorder = ref.frameName.isEmpty }
        let outset: CGFloat = photoBorder ? 0 : 6
        return ZStack {
            if photoBorder {
                RoundedRectangle(cornerRadius: Metrics.imageCorner)
                    .strokeBorder(Palette.ink, lineWidth: 3)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
            ForEach(HandleCorner.allCases, id: \.self) { corner in
                Circle()
                    .fill(Palette.warmWhite)
                    .overlay(Circle().strokeBorder(line, lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .offset(
                        x: corner.sign.x * (size.width / 2 + outset),
                        y: corner.sign.y * (size.height / 2 + outset)
                    )
                    .gesture(resizeGesture(item, corner: corner))
            }
        }
    }

    private func resizeGesture(_ item: CanvasItem, corner: HandleCorner) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($activeResize) { value, state, _ in
                state = ActiveResize(itemID: item.id, corner: corner, translation: value.translation)
            }
            .onEnded { value in
                editor.beginChange()
                editor.resize(itemID: item.id, to: CGSize(
                    width: item.size.width + corner.sign.x * value.translation.width,
                    height: item.size.height + corner.sign.y * value.translation.height
                ))
                editor.move(itemID: item.id, to: CGPoint(
                    x: item.position.x + value.translation.width / 2,
                    y: item.position.y + value.translation.height / 2
                ))
            }
    }

    // MARK: Context menu

    @ViewBuilder private func contextMenu(for item: CanvasItem) -> some View {
        editEntry(for: item)
        favoriteEntry(for: item)

        Button {
            editor.duplicate(itemID: item.id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            editor.bringToFront(itemID: item.id)
        } label: {
            Label("Bring to front", systemImage: "square.3.layers.3d.top.filled")
        }
        Button {
            editor.sendToBack(itemID: item.id)
        } label: {
            Label("Send to back", systemImage: "square.3.layers.3d.bottom.filled")
        }
        Button(role: .destructive) {
            deleteWithToast(item.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteWithToast(_ id: CanvasItem.ID) {
        editor.delete(itemID: id)
        show(toast: .deleted(changeCount: editor.changeCount))
    }

    func show(toast kind: Toast) {
        toastDismiss?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { toast = kind }
        toastDismiss = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { toast = nil }
        }
    }

    @ViewBuilder private func toastView(_ kind: Toast) -> some View {
        HStack(spacing: 14) {
            switch kind {
            case .deleted(let changeCount), .added(let changeCount):
                Text(kind.isAdded ? "Added - drag to move" : "Deleted")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                // Only the delete: once something newer is on the page, the
                // canvas-wide undo would take that back instead.
                Button("Undo") {
                    if editor.changeCount == changeCount { editor.undo() }
                    toastDismiss?.cancel()
                    withAnimation(.easeIn(duration: 0.18)) { toast = nil }
                }
                .font(.miraLabel.weight(.semibold))
                .foregroundStyle(Palette.onInk)
                .disabled(editor.changeCount != changeCount)
                .accessibilityIdentifier("toast.undo")
            case .favorited:
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.onInk)
                Text("Saved to Favorites")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(Palette.ink.opacity(0.92)))
    }

    // MARK: Sound helpers

    private func clipID(of item: CanvasItem) -> UUID? {
        if case .sound(let clip) = item.content { return clip.id }
        return nil
    }

    private func togglePlay(_ item: CanvasItem) {
        guard case .sound(let clip) = item.content else { return }
        player.toggle(clip: clip, store: soundStore)
    }

    /// Internal (not private) so CanvasBoardView+Menu.swift can offer it.
    func beginNoteEdit(_ item: CanvasItem) {
        guard case .sound(let clip) = item.content else { return }
        noteDraft = clip.note
        noteEditingItem = item.id
    }

    private var noteAlertShown: Binding<Bool> {
        Binding(
            get: { noteEditingItem != nil },
            set: { if !$0 { noteEditingItem = nil } }
        )
    }
}
