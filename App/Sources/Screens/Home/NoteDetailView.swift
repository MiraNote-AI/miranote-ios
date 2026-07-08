import MiraNoteKit
import SwiftUI

/// A single note opened from a collection: read and edit its title and body,
/// saved back to the collection when you leave.
struct NoteDetailView: View {
    var viewModel: HomeViewModel
    let collectionID: MemoryCollection.ID
    let noteID: Memory.ID
    var onBack: () -> Void = {}

    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var loaded = false

    private var note: Memory? {
        viewModel.note(noteID, in: collectionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            editor
        }
        .screenBackground()
        .task {
            guard !loaded else { return }
            noteTitle = note?.title ?? ""
            noteBody = note?.body ?? ""
            loaded = true
        }
        .onDisappear(perform: persist)
    }

    private var header: some View {
        HStack {
            Button {
                persist()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Palette.onInk.opacity(0.6)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(note?.createdAt ?? Date(), format: .dateTime.month().day().year())
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Title", text: $noteTitle, axis: .vertical)
                    .font(.miraPageTitle)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.forest)
                    .accessibilityIdentifier("note.title")

                Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)

                bodyEditor
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
        }
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if noteBody.isEmpty {
                Text("Write your memory...")
                    .font(.miraBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $noteBody)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
                .accessibilityIdentifier("note.body")
        }
    }

    private func persist() {
        guard loaded else { return }
        viewModel.updateNote(noteID, in: collectionID, title: noteTitle, body: noteBody)
    }
}
