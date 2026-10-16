import AVFoundation
import MiraNoteKit
import SwiftUI

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
    /// Non-nil while a picture waits to be placed: the tap places it there.
    var onPlaceTap: ((CGPoint) -> CanvasItem.ID?)?
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
    var lifted: Binding<LiftedElement?> = .constant(nil)
    /// While Voice records: where the take will land, in page points.
    var pendingSoundMarker: CGPoint?

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
    @State private var scrollTarget: CanvasItem.ID?
    /// Where the reveal anchor sits while a reveal is in flight.
    @State private var revealFrame: CGRect?
    @State private var toast: Toast?
    @State private var toastDismiss: Task<Void, Never>?

    /// Bottom-edge receipts; deleted carries the one-tap Undo, good while
    /// the delete is still the page's newest change (`changeCount`).
    enum Toast {
        case deleted(changeCount: Int)
        case favorited
    }

    private let minBoardHeight: CGFloat = 620
    private static let revealAnchorID = "canvas.revealAnchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // The page is a fixed-width column, centred in whatever
                // room the device has -- not the screen minus padding,
                // which made the same page a different width on every
                // phone and disagree with its own export.
                board
            }
            // The card holds still; the page scrolls inside it.
            .canvasCard()
            // The page keeps its full height under the keyboard while
            // writing: the block rides in the upper third, clear of the
            // keyboard and the text chrome over the page's lower part.
            .onChange(of: editor.editingTextItemID) { _, id in
                bring(id, into: proxy, anchor: UnitPoint(x: 0.5, y: 0.3))
            }
            .onChange(of: scrollTarget) { _, id in bring(id, into: proxy) }
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
        .scrollDisabled(editor.selectedItemID != nil && editor.editingTextItemID == nil)
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
            if phase == nil { lifted.wrappedValue = nil }
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

    /// At least the card's own height, so the page always fills the card.
    private var boardHeight: CGFloat {
        max(minBoardHeight, visibleFrame.height, editor.contentBottom + 240)
    }

    private func bring(_ id: CanvasItem.ID?, into proxy: ScrollViewProxy, anchor: UnitPoint = .center) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: anchor) }
    }

    /// The page itself -- its backdrop stretches with the content, so the
    /// background never "runs out".
    private var paper: some View {
        PageBackdrop(memory: editor.memory)
            // One tap path, so placing and deselecting can never both fire.
            .onTapGesture(coordinateSpace: .local) { point in
                if let onPlaceTap {
                    scrollTarget = onPlaceTap(point)
                } else if let onEndWritingThen {
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
    }

    /// The moving element's box on screen, translation included: the scene
    /// draws the lifted copy exactly there.
    private func liftReporter(_ item: CanvasItem, rotation: Double) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { lift(item, frame: geo.frame(in: .global), rotation: rotation) }
                .onChange(of: geo.frame(in: .global)) { _, frame in
                    lift(item, frame: frame, rotation: rotation)
                }
        }
    }

    private func lift(_ item: CanvasItem, frame: CGRect, rotation: Double) {
        // The drop's own frame change can land after the move ended: never
        // bring the copy back then.
        guard let activeMove, activeMove.itemID == item.id else { return }
        lifted.wrappedValue = LiftedElement(item: item, frame: frame, rotation: rotation, finger: activeMove.location)
    }

    /// Model geometry plus any in-flight gesture translation for this item.
    /// The model itself only changes when a gesture ends, so a cancelled
    /// gesture reverts visually for free.
    private func effectiveGeometry(_ item: CanvasItem) -> ElementGeometry {
        var position = item.position
        var size = item.size
        var rotation = item.rotation
        if let move = activeMove, move.itemID == item.id {
            position.x += move.translation.width
            position.y += move.translation.height
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
                    x: item.position.x + value.translation.width,
                    y: item.position.y + value.translation.height
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
            case .deleted(let changeCount):
                Text("Deleted")
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
