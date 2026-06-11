import MiraNoteKit
import SwiftUI

/// Sketch 1: hamburger + avatar, "Start a memory", collections row,
/// "What is in your mind?" pill. Empty state per D3.
struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var activeMemory: Memory?
    @State private var showsQuickCapturePlaceholder = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer(minLength: 24)

                Button {
                    activeMemory = viewModel.startMemory()
                } label: {
                    Label("Start a memory", systemImage: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(PillButtonStyle(prominent: true))

                collectionsSection

                Spacer()

                whatsOnYourMindPill
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Text("Settings and more arrive later")
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
            }
            .navigationDestination(item: $activeMemory) { memory in
                CanvasView(memory: memory) { saved in
                    viewModel.file(saved, underCollectionTitled: "My memories")
                }
            }
            .sheet(isPresented: $showsQuickCapturePlaceholder) {
                quickCapturePlaceholder
            }
        }
    }

    @ViewBuilder private var collectionsSection: some View {
        if viewModel.showsEmptyStateHint {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No collections yet. Start your first memory and it will live here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.collections) { collection in
                        CollectionCard(title: collection.title, count: collection.memories.count)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var whatsOnYourMindPill: some View {
        Button {
            showsQuickCapturePlaceholder = true
        } label: {
            HStack {
                Image(systemName: "mic.badge.plus")
                Text("What is in your mind?")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Spec Q4: the chat-style entry point is undecided; placeholder only.
    private var quickCapturePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Quick capture is on its way")
                .font(.headline)
            Text("This entry point is waiting on a design decision (spec Q4).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .presentationDetents([.fraction(0.3)])
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel())
}
