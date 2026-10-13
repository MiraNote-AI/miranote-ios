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
    var onOpenTrash: () -> Void = {}

    @State private var prompt = ""
    @State private var addingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)

                Text(HomeView.dateLine(for: .now))
                    .font(.miraDate)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(1)
                    .padding(.bottom, 14)

                hero
                    .padding(.bottom, 24)

                // Handoff screen 01: the large Start button leads, the
                // retrieval pill follows it. The pill still asks about the
                // past -- its icon and placeholder say so -- it never starts
                // a note.
                startButton
                    .padding(.bottom, 28)

                quickPill
                    .padding(.bottom, 22)

                grid

                if !viewModel.trash.isEmpty {
                    Button {
                        onOpenTrash()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 12))
                            Text("Recently deleted (\(viewModel.trash.count))")
                                .font(.miraCaption)
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.trash")
                    .padding(.top, 14)
                }
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
            Image(systemName: "person")
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Palette.ink)
    }

    private var hero: some View {
        VStack(spacing: 2) {
            Text("Your memory,")
            Text("beautifully made.")
        }
        .font(.miraHero)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The handoff's 226 x 92 pt ink button with a long warm shadow.
    private var startButton: some View {
        Button(action: onStart) {
            Text("Start a memory")
                .font(Sans.font(size: 24, weight: 500))
                .foregroundStyle(Palette.onInk)
                .frame(width: 226, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 36)
                        .fill(Palette.ink)
                        .shadow(color: Color(hex: 0x544738).opacity(0.16), radius: 28, y: 30)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("Start a memory")
    }

    private var quickPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.tan.opacity(0.7)))

            TextField("", text: $prompt)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.send)
                .onSubmit(submitPrompt)
                .accessibilityIdentifier("quick.field")
                .overlay(alignment: .leading) {
                    if prompt.isEmpty {
                        Text("When was my Paris trip?")
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
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Palette.warmWhite.opacity(0.8))
                .shadow(color: Color(hex: 0x544738).opacity(0.08), radius: 16, y: 16)
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
                .font(.miraLabel)
        }
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: HomeCollectionCard.height)
        .background(
            RoundedRectangle(cornerRadius: HomeCollectionCard.corner)
                .fill(Palette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: HomeCollectionCard.corner)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
        )
    }

    /// The handoff's four card colors (screen 01), cycled by position. Its
    /// warm-white titles read at 2.1-3.5:1 on the grey, brown and tan cards,
    /// below the 4.5:1 a 19 pt title needs, so grey and brown are darkened
    /// along their hue (4.6:1) and the tan card takes ink (7:1).
    private func cardStyle(_ index: Int) -> CardStyle {
        switch index % 4 {
        case 1:
            return CardStyle(background: Palette.forest, inner: Color(hex: 0xB6C2BA), title: Palette.onInk)
        case 2:
            return CardStyle(background: Color(hex: 0x706E62), inner: Color(hex: 0x504E45), title: Palette.onInk)
        case 3:
            return CardStyle(background: Color(hex: 0xC1A47E), inner: Color(hex: 0xD9CDBA), title: Palette.ink)
        default:
            return CardStyle(background: Color(hex: 0x7A6B64), inner: Color(hex: 0xA39088), title: Palette.onInk)
        }
    }

    private func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickCapture(trimmed)
        prompt = ""
    }
}

/// One collection card in the Home grid (handoff screen 01): a tall 26 pt
/// rounded card, the title in up to two lines at the top, the note count,
/// and a soft cover block resting at the bottom.
struct HomeCollectionCard: View {
    static let height: CGFloat = 188
    static let corner: CGFloat = 26

    let title: String
    let count: Int
    var background: Color
    var inner: Color
    var titleColor: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Sans.font(size: 19, weight: 400))
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(count) note\(count == 1 ? "" : "s")")
                .font(Sans.font(size: 11, weight: 400))
                .foregroundStyle(titleColor)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 18)
                .fill(inner)
                .frame(height: 60)
                .padding(.horizontal, 12)
        }
        .padding(.top, 22)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(background)
                .shadow(color: Color(hex: 0x544738).opacity(0.1), radius: 17, y: 18)
        )
    }
}

/// The palette a Home collection card is drawn in, cycled by grid position.
private struct CardStyle {
    let background: Color
    let inner: Color
    let title: Color
}

extension HomeView {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE,\nMMMM d"
        return formatter
    }()

    /// The editorial dateline under the wordmark: "WEDNESDAY,\nJULY 8".
    /// Pinned to English -- all of the app's copy is.
    static func dateLine(for date: Date) -> String {
        dateFormatter.string(from: date).uppercased()
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
}
