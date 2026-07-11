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
}
