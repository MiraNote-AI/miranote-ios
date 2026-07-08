import MiraNoteKit
import SwiftUI

/// A collection opened from Home: its notes listed as rows, with an add action.
/// Reads the collection live from the view model by id, so adds appear at once.
struct CollectionDetailView: View {
    var viewModel: HomeViewModel
    let collectionID: MemoryCollection.ID
    var onBack: () -> Void = {}
    var onOpenNote: (Memory) -> Void = { _ in }

    private var collection: MemoryCollection? {
        viewModel.collection(collectionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let collection, !collection.memories.isEmpty {
                notesList(collection)
            } else {
                emptyState
            }
        }
        .screenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Palette.onInk.opacity(0.6)))
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    viewModel.addNote(titled: "New note", to: collectionID)
                } label: {
                    Label("Add note", systemImage: "plus")
                }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("note.add")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(collection?.title ?? "Collection")
                    .font(.miraPageTitle)
                    .foregroundStyle(Palette.ink)
                Text(noteCountLabel)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
        }
    }

    private var noteCountLabel: String {
        let count = collection?.memories.count ?? 0
        return "\(count) note\(count == 1 ? "" : "s")"
    }

    private func notesList(_ collection: MemoryCollection) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(collection.memories) { memory in
                    Button {
                        onOpenNote(memory)
                    } label: {
                        noteRow(memory)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.\(memory.title)")
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 18)
        }
    }

    private func noteRow(_ memory: Memory) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.cardFill)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "doc.text").foregroundStyle(Palette.taupe))
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.title.isEmpty ? "Untitled" : memory.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(memory.createdAt, format: .dateTime.month().day().year())
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.onInk.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Palette.textSecondary)
            Text("No notes yet")
                .font(.miraPageTitle)
                .foregroundStyle(Palette.ink)
            Text("Tap Add note to start this collection.")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
