import MiraNoteKit
import SwiftUI

// The per-type "Edit ..." context-menu entry (split from
// CanvasBoardView.swift for the file and function length caps).
extension CanvasBoardView {
    @ViewBuilder func editEntry(for item: CanvasItem) -> some View {
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
    }

    /// "Favorite" for anything with stored pixels: saves a copy to the
    /// Favorites shelf for reuse across memories.
    @ViewBuilder func favoriteEntry(for item: CanvasItem) -> some View {
        switch item.content {
        case .image(let ref):
            if !ref.fileName.isEmpty { favoriteButton(item) }
        case .sticker(let sticker):
            if !sticker.fileName.isEmpty { favoriteButton(item) }
        case .text, .sound:
            EmptyView()
        }
    }

    private func favoriteButton(_ item: CanvasItem) -> some View {
        Button {
            onFavorite(item)
            show(toast: .favorited)
        } label: {
            Label("Favorite", systemImage: "heart")
        }
    }
}
