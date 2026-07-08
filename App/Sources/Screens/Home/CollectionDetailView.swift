import MiraNoteKit
import SwiftUI

/// Journal detail (v2.1): a two-column grid of page covers grouped by the
/// month of the memory date. Tap opens reading mode; long-press offers
/// move / delete (delete goes to the 30-day bin, the only delete path).
struct CollectionDetailView: View {
    var viewModel: HomeViewModel
    let collectionID: MemoryCollection.ID
    var onBack: () -> Void = {}
    var onOpenNote: (Memory) -> Void = { _ in }

    private var collection: MemoryCollection? {
        viewModel.collection(collectionID)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(monthGroups, id: \.label) { group in
                    section(group)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top) {
            header
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.addNote(titled: "New note", to: collectionID)
            } label: {
                Text("+ New memory")
                    .font(.miraPill)
                    .foregroundStyle(Palette.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note.add")
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 6)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Home")
                }
            }
            .buttonStyle(SoftPill())
            Spacer()
            VStack(spacing: 1) {
                Text(collection?.title ?? "")
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
                Text("\(collection?.memories.count ?? 0) pages")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            // Balances the leading pill so the title stays centered.
            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 8)
        .background(Palette.paper.opacity(0.94))
    }

    // MARK: Month groups (by memory date, newest first)

    private struct MonthGroup {
        let label: String
        let memories: [Memory]
    }

    private var monthGroups: [MonthGroup] {
        guard let memories = collection?.memories else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let sorted = memories.sorted { $0.memoryDate > $1.memoryDate }
        var order: [String] = []
        var buckets: [String: [Memory]] = [:]
        for memory in sorted {
            let label = formatter.string(from: memory.memoryDate).uppercased()
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(memory)
        }
        return order.map { MonthGroup(label: $0, memories: buckets[$0] ?? []) }
    }

    @ViewBuilder private func section(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.label)
                .font(.system(size: 11, weight: .medium))
                .kerning(1.6)
                .foregroundStyle(Palette.textSecondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 14
            ) {
                ForEach(group.memories) { memory in
                    cover(memory)
                }
            }
        }
    }

    private func cover(_ memory: Memory) -> some View {
        Button {
            onOpenNote(memory)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                PageCoverView(memory: memory, coverWidth: 164, coverHeight: 190)
                Text(memory.title.isEmpty ? "Untitled" : memory.title)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            // The cover itself ignores touches (Color.clear + hit-disabled
            // page), so give the whole label a tappable shape.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.\(memory.title)")
        .contextMenu {
            ForEach(otherCollections) { destination in
                Button {
                    viewModel.move(memory.id, from: collectionID, to: destination.id)
                } label: {
                    Label("Move to \(destination.title)", systemImage: "arrow.turn.up.right")
                }
            }
            Button(role: .destructive) {
                viewModel.deleteNote(memory.id, from: collectionID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var otherCollections: [MemoryCollection] {
        viewModel.collections.filter { $0.id != collectionID }
    }
}
