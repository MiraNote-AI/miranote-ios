import MiraNoteKit
import SwiftUI

/// Flow 7 Scene 01: the wordmark row, the date, the editorial hero, the ink
/// "Start a memory" pill, a quick-capture field, and the collection grid --
/// now driven by the user's real, persisted note collections.
struct HomeView: View {
    var viewModel: HomeViewModel
    var onStart: () -> Void = {}
    var onQuickCapture: (String) -> Void = { _ in }
    var onOpenCollection: (MemoryCollection) -> Void = { _ in }

    @State private var prompt = ""
    @State private var addingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)

                Text("MONDAY,\nJUNE 22")
                    .font(.miraDate)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(1)
                    .padding(.bottom, 16)

                hero
                    .padding(.bottom, 24)

                Button("Start a memory", action: onStart)
                    .buttonStyle(PrimaryPill(horizontalPadding: 30, verticalPadding: 15))
                    .padding(.bottom, 18)

                quickPill
                    .padding(.bottom, 22)

                grid
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .alert("New collection", isPresented: $addingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                viewModel.addCollection(title: newCollectionName)
                newCollectionName = ""
            }
        } message: {
            Text("Name your new notebook.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("MiraNote")
                .font(.miraLogo)
            Spacer()
            Image(systemName: "bell")
            Image(systemName: "person")
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Palette.ink)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your memory,")
            Text("beautifully made.")
        }
        .font(.miraHero)
        .foregroundStyle(Palette.ink)
    }

    private var quickPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)

            TextField("", text: $prompt)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.send)
                .onSubmit(submitPrompt)
                .overlay(alignment: .leading) {
                    if prompt.isEmpty {
                        Text("what I eat...")
                            .font(.miraBody)
                            .foregroundStyle(Palette.textSecondary)
                            .allowsHitTesting(false)
                    }
                }

            if !prompt.isEmpty {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quick.send")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Palette.onInk.opacity(0.55))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
    }

    private var grid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(viewModel.collections.enumerated()), id: \.element.id) { index, collection in
                Button {
                    onOpenCollection(collection)
                } label: {
                    card(for: collection, index: index)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("collection.\(collection.title)")
            }

            Button {
                addingCollection = true
            } label: {
                newCollectionCard
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("collection.new")
        }
    }

    private func card(for collection: MemoryCollection, index: Int) -> some View {
        let style = cardStyle(index)
        return HomeCollectionCard(
            title: collection.title,
            count: collection.memories.count,
            background: style.background,
            inner: style.inner,
            titleColor: style.title
        )
    }

    private var newCollectionCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
            Text("New collection")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 122)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Palette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
        )
    }

    private func cardStyle(_ index: Int) -> CardStyle {
        switch index % 4 {
        case 1:
            return CardStyle(background: Palette.forest, inner: Palette.sage.opacity(0.7), title: Palette.onInk)
        case 2:
            return CardStyle(
                background: Palette.sage.opacity(0.45),
                inner: Palette.taupe.opacity(0.55),
                title: Palette.ink
            )
        case 3:
            return CardStyle(
                background: Palette.tan.opacity(0.6),
                inner: Palette.onInk.opacity(0.7),
                title: Palette.ink
            )
        default:
            return CardStyle(background: Palette.cardFill, inner: Palette.taupe.opacity(0.45), title: Palette.ink)
        }
    }

    private func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickCapture(trimmed)
        prompt = ""
    }
}

/// One book-spine collection card in the Home grid.
struct HomeCollectionCard: View {
    let title: String
    let count: Int
    var background: Color
    var inner: Color
    var titleColor: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            RoundedRectangle(cornerRadius: 12)
                .fill(inner)
                .frame(height: 44)
            Text("\(count) note\(count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(titleColor.opacity(0.6))
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20).fill(background))
    }
}

/// The palette a Home collection card is drawn in, cycled by grid position.
private struct CardStyle {
    let background: Color
    let inner: Color
    let title: Color
}

#Preview {
    HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
}
