import AVFoundation
import MiraNoteKit
import SwiftUI

/// The v2.1 infinite canvas: a vertically scrolling page of freely placed
/// elements. Gesture grammar ("selected moves, unselected scrolls"): tap
/// selects, tap on empty paper deselects, drag moves only the selected
/// element, long-press opens the context menu (the only delete path), corner
/// handles resize, and two fingers rotate.
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

    @State private var player = SoundPlayer()
    // Transient gesture values: @GestureState resets automatically when a
    // gesture is CANCELLED (context menu, incoming call, backgrounding), so
    // no stale origin can teleport an element or skip an undo snapshot. The
    // model commits once, on gesture end.
    @GestureState private var activeMove: ActiveMove?
    @GestureState private var activeResize: ActiveResize?
    @GestureState private var activeRotation: ActiveRotation?
    @State private var noteDraft = ""
    @State private var noteEditingItem: CanvasItem.ID?
    @State private var showsDeleteToast = false
    @State private var toastDismiss: Task<Void, Never>?

    private let minBoardHeight: CGFloat = 620

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                board
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 8)
            }
            .onChange(of: editor.editingTextItemID) { _, editing in
                guard let editing else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(editing, anchor: .center)
                }
            }
        }
        // The gesture grammar, literally: with a selection, dragging moves
        // the element (UIScrollView would otherwise steal vertical pans);
        // with none, dragging scrolls the page.
        .scrollDisabled(editor.selectedItemID != nil)
        .overlay(alignment: .bottom) {
            if showsDeleteToast {
                deleteToast
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

    private var board: some View {
        ZStack(alignment: .topLeading) {
            paper
            if editor.items.isEmpty {
                Text("Tap a tool below, or tell Mira about today.")
                    .font(.miraBody)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 240)
                    .multilineTextAlignment(.center)
                    .position(x: 180, y: 200)
                    .allowsHitTesting(false)
            }
            ForEach(editor.orderedItems) { item in
                element(item)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: boardHeight)
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

    private var boardHeight: CGFloat {
        max(minBoardHeight, editor.contentBottom + 240)
    }

    /// The page itself -- a warm paper sheet whose soft gradient stretches
    /// with the content, so the background never "runs out".
    private var paper: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [Palette.onInk, Palette.cardFill.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
            )
            .onTapGesture {
                editor.endEditingText()
                editor.select(nil)
                textFocus.wrappedValue = nil
            }
    }

    // MARK: Elements

    @ViewBuilder private func element(_ item: CanvasItem) -> some View {
        let isSelected = editor.selectedItemID == item.id
        let isEditing = editor.editingTextItemID == item.id
        let geometry = effectiveGeometry(item)

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
        .rotationEffect(.degrees(geometry.rotation))
        .position(geometry.position)
        .id(item.id)
        .onTapGesture { handleTap(item, isSelected: isSelected) }
        .gesture(isSelected && !isEditing ? moveGesture(item) : nil)
        .simultaneousGesture(isSelected ? rotateGesture(item) : nil)
        .contextMenu { contextMenu(for: item) }
        .modifier(BreathingLock(active: workingItemIDs.contains(item.id)))
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

    private func handleTap(_ item: CanvasItem, isSelected: Bool) {
        if !isSelected {
            editor.select(item.id)
            return
        }
        if case .text = item.content {
            editor.startEditingText(item.id)
            textFocus.wrappedValue = item.id
        }
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

    private func moveGesture(_ item: CanvasItem) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($activeMove) { value, state, _ in
                state = ActiveMove(itemID: item.id, translation: value.translation)
            }
            .onEnded { value in
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

    /// Dashed selection frame with four corner dots. Corner drags resize
    /// around the opposite corner; deltas are applied in unrotated space (a
    /// deliberate simplification -- scrapbook tilts stay small).
    private func handles(for item: CanvasItem, size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Palette.ink.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
            ForEach(HandleCorner.allCases, id: \.self) { corner in
                Circle()
                    .fill(Palette.onInk)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.4))
                    .frame(width: 14, height: 14)
                    .contentShape(Circle().inset(by: -10))
                    .offset(
                        x: corner.sign.x * size.width / 2,
                        y: corner.sign.y * size.height / 2
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

    // MARK: Context menu (the only delete path)

    @ViewBuilder private func contextMenu(for item: CanvasItem) -> some View {
        switch item.content {
        case .text:
            Button {
                editor.startEditingText(item.id)
                textFocus.wrappedValue = item.id
            } label: {
                Label("Edit text", systemImage: "character.cursor.ibeam")
            }
        case .sound:
            Button {
                beginNoteEdit(item)
            } label: {
                Label("Edit note", systemImage: "text.bubble")
            }
        case .image(let ref):
            if !ref.fileName.isEmpty {
                Button {
                    onEditImage(item.id)
                } label: {
                    Label("Edit photo", systemImage: "camera.filters")
                }
            }
        case .sticker(let sticker):
            if !sticker.fileName.isEmpty {
                Button {
                    onEditSticker(item.id)
                } label: {
                    Label("Edit sticker", systemImage: "wand.and.stars")
                }
            }
        }

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
        toastDismiss?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { showsDeleteToast = true }
        toastDismiss = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { showsDeleteToast = false }
        }
    }

    private var deleteToast: some View {
        HStack(spacing: 14) {
            Text("Deleted")
                .font(.miraLabel)
                .foregroundStyle(Palette.onInk)
            Button("Undo") {
                editor.undo()
                toastDismiss?.cancel()
                withAnimation(.easeIn(duration: 0.18)) { showsDeleteToast = false }
            }
            .font(.miraLabel.weight(.semibold))
            .foregroundStyle(Palette.onInk)
            .accessibilityIdentifier("toast.undo")
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

    private func beginNoteEdit(_ item: CanvasItem) {
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
