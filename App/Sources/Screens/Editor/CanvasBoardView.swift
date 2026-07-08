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

    @State private var player = SoundPlayer()
    @State private var moveOrigin: CGPoint?
    @State private var rotationOrigin: Double?
    @State private var resizeOrigin: (position: CGPoint, size: CGSize)?
    @State private var noteDraft = ""
    @State private var noteEditingItem: CanvasItem.ID?
    @State private var showsDeleteToast = false
    @State private var toastDismiss: Task<Void, Never>?

    private let minBoardHeight: CGFloat = 620

    var body: some View {
        ScrollView(showsIndicators: false) {
            board
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 8)
        }
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
            ForEach(editor.orderedItems) { item in
                element(item)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: boardHeight)
        // No identifier on the container: SwiftUI cascades a parent
        // accessibilityIdentifier onto contained elements, masking child
        // ids like canvas.textEditor.
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
        .frame(width: item.size.width, height: item.size.height)
        .overlay {
            if isSelected && !isEditing {
                handles(for: item)
            }
        }
        .rotationEffect(.degrees(item.rotation))
        .position(item.position)
        .onTapGesture { handleTap(item, isSelected: isSelected) }
        .gesture(isSelected && !isEditing ? moveGesture(item) : nil)
        .simultaneousGesture(isSelected ? rotateGesture(item) : nil)
        .contextMenu { contextMenu(for: item) }
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
            set: { editor.setText(itemID: item.id, to: $0) }
        )
    }
}

// MARK: - Gestures, menu, toast, sound

extension CanvasBoardView {
    // MARK: Gestures

    private func moveGesture(_ item: CanvasItem) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if moveOrigin == nil {
                    moveOrigin = editor.item(item.id)?.position
                    editor.beginChange()
                }
                guard let origin = moveOrigin else { return }
                editor.move(itemID: item.id, to: CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                ))
            }
            .onEnded { _ in moveOrigin = nil }
    }

    private func rotateGesture(_ item: CanvasItem) -> some Gesture {
        RotateGesture()
            .onChanged { value in
                if rotationOrigin == nil {
                    rotationOrigin = editor.item(item.id)?.rotation
                    editor.beginChange()
                }
                guard let origin = rotationOrigin else { return }
                editor.rotate(itemID: item.id, degrees: origin + value.rotation.degrees)
            }
            .onEnded { _ in rotationOrigin = nil }
    }

    /// Dashed selection frame with four corner dots. Corner drags resize
    /// around the opposite corner; deltas are applied in unrotated space (a
    /// deliberate simplification -- scrapbook tilts stay small).
    private func handles(for item: CanvasItem) -> some View {
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
                    .offset(
                        x: corner.sign.x * item.size.width / 2,
                        y: corner.sign.y * item.size.height / 2
                    )
                    .gesture(resizeGesture(item, corner: corner))
            }
        }
    }

    private func resizeGesture(_ item: CanvasItem, corner: HandleCorner) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeOrigin == nil {
                    guard let current = editor.item(item.id) else { return }
                    resizeOrigin = (current.position, current.size)
                    editor.beginChange()
                }
                guard let origin = resizeOrigin else { return }
                editor.resize(itemID: item.id, to: CGSize(
                    width: origin.size.width + corner.sign.x * value.translation.width,
                    height: origin.size.height + corner.sign.y * value.translation.height
                ))
                editor.move(itemID: item.id, to: CGPoint(
                    x: origin.position.x + value.translation.width / 2,
                    y: origin.position.y + value.translation.height / 2
                ))
            }
            .onEnded { _ in resizeOrigin = nil }
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
        case .image, .sticker:
            EmptyView()
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

/// Which corner a resize handle sits on; `sign` maps drag translation to
/// size growth for that corner.
private enum HandleCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var sign: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeading: return (-1, -1)
        case .topTrailing: return (1, -1)
        case .bottomLeading: return (-1, 1)
        case .bottomTrailing: return (1, 1)
        }
    }
}
