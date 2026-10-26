import MiraNoteKit
import SwiftUI

/// Handoff screen 01: the wordmark row with the profile circle, the
/// two-line dateline, the editorial hero, the ink "Start a memory" button,
/// the retrieval prompt bar, and the collection grid -- driven by the
/// user's real, persisted note collections. Beyond the design: a "New
/// collection" card closes the grid and "Recently deleted" sits under it
/// when the bin holds anything.
struct HomeView: View {
    var viewModel: HomeViewModel
    var onStart: () -> Void = {}
    var onQuickCapture: (String) -> Void = { _ in }
    var onOpenCollection: (MemoryCollection) -> Void = { _ in }
    var onOpenTrash: () -> Void = {}
    var onOpenStarJar: () -> Void = {}

    @State private var prompt = ""
    /// The ask bar's keyboard: a tap on the page or a scroll lowers it.
    @FocusState private var promptFocused: Bool
    @State private var addingCollection = false
    @State private var newCollectionName = ""

    /// The dateline's warm grey (#8F8477), also used for the extras the
    /// design does not draw (New collection, Recently deleted).
    static let dateColor = Color(hex: 0x8F8477)

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Vertical rhythm from the handoff's frames, in Josefin's 1.0 em
            // line boxes (the CSS 1.18 line height adds its half-leading to
            // the gaps here).
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 8)
                dateline
                    .padding(.bottom, 9)
                hero
                    .padding(.bottom, 28)
                startButton
                    .padding(.bottom, 27)
                promptBar
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
                                .font(Sans.font(size: 14, weight: 600))
                        }
                        // Not drawn by the design: textSecondary (6.1:1 on
                        // the paper), not the 3.3:1 date color.
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.trash")
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, Metrics.chromeInset)
            // The profile circle rises 6 pt into the status-bar band: the
            // wordmark, not the circle, lines up with the editor's nav row.
            .padding(.top, -6)
            .padding(.bottom, 28)
            // A tap that no button takes lowers the ask bar's keyboard; the
            // words stay in the bar.
            .contentShape(Rectangle())
            .onTapGesture { promptFocused = false }
        }
        .scrollDismissesKeyboard(.immediately)
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

    /// Wordmark (Bold 15, #25231F) and the 38 pt glass profile circle. The
    /// design's bell is left out: nothing stands behind it yet.
    private var header: some View {
        HStack(alignment: .top) {
            Text("MiraNote")
                .font(.miraLogo)
                .foregroundStyle(Color(hex: 0x25231F))
                .padding(.top, 9)
            Spacer()
            // Not drawn by the handoff: the star jar, a twin of the profile
            // circle beside it.
            Button(action: onOpenStarJar) {
                glassCircle("home.starJar")
                    .padding(3)
                    .contentShape(Circle())
                    .padding(-3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Star jar")
            .accessibilityIdentifier("home.starJar")
            .padding(.trailing, 10)
            glassCircle("home.profile")
                .accessibilityHidden(true)
        }
    }

    private func glassCircle(_ asset: String) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundStyle(Color(hex: 0x635B50))
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.58))
                    .overlay(Circle().strokeBorder(Color(hex: 0x48433B).opacity(0.12), lineWidth: 1))
                    .shadow(color: Color(hex: 0x544738).opacity(0.025), radius: 8, y: 6)
            )
    }

    /// "MONDAY," over an indented "JUNE 22", Josefin Bold 24 in #8F8477.
    private var dateline: some View {
        let lines = HomeView.dateLines(for: .now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(lines.weekday)
            Text(lines.day)
                .padding(.leading, 80)
        }
        .font(.miraDate)
        .foregroundStyle(Self.dateColor)
        .accessibilityElement(children: .combine)
    }

    /// Two lines at the design's 1.02 line height: Fraunces' own line box
    /// is ~7 pt taller than 1769_W05's, so the lines overlap by that much.
    private var hero: some View {
        VStack(spacing: -7) {
            Text("Your memory,")
            Text("beautifully made.")
        }
        .font(.miraHero)
        .foregroundStyle(Color(hex: 0x24221E))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The handoff's 226 x 92 pt ink button with a long warm shadow.
    private var startButton: some View {
        Button(action: onStart) {
            Text("Start a memory")
                .font(Sans.font(size: 24.6, weight: 700))
                .foregroundStyle(Color(hex: 0xFFFAF3))
                // One line: the button is drawn 226 wide.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
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

    /// The 41 pt retrieval bar: the four-point star in a 26 pt #C6B298
    /// circle, then a Bold 16 field at ink@0.5. It asks about the past and
    /// opens the Mira chat; it never starts a note.
    private var promptBar: some View {
        HStack(spacing: 12) {
            Image("home.spark")
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color(hex: 0x635B50))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(hex: 0xC6B298)))
                .accessibilityHidden(true)

            TextField("", text: $prompt)
                .font(Sans.font(size: 16, weight: 700))
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.send)
                .onSubmit(submitPrompt)
                .focused($promptFocused)
                .accessibilityIdentifier("quick.field")
                .overlay(alignment: .leading) {
                    if prompt.isEmpty {
                        Text("When was my Paris trip?")
                            .font(Sans.font(size: 16, weight: 700))
                            .foregroundStyle(Palette.ink.opacity(0.5))
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
        .padding(.trailing, 9)
        .frame(height: 41)
        .background(
            Capsule()
                .fill(Color(hex: 0xF6F5F1))
                .shadow(color: Color(hex: 0x544738).opacity(0.08), radius: 16, y: 16)
        )
        // A tap anywhere on the bar is for its field, not the page's tap
        // that lowers the keyboard.
        .contentShape(Capsule())
        .onTapGesture { promptFocused = true }
    }

    private var grid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 26),
            GridItem(.flexible(), spacing: 26)
        ]
        return LazyVGrid(columns: columns, spacing: 24) {
            ForEach(Array(viewModel.collections.enumerated()), id: \.element.id) { index, collection in
                Button {
                    onOpenCollection(collection)
                } label: {
                    HomeCollectionCard(title: collection.title, style: HomeCollectionCard.Style.cycle(index))
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

    /// Not drawn by the handoff: an outlined card in the grid's geometry,
    /// labelled in the dateline's grey.
    private var newCollectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
            Text("New collection")
                .font(Sans.font(size: 22, weight: 700))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Self.dateColor)
        .padding(.top, 26)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, minHeight: HomeCollectionCard.height, maxHeight: HomeCollectionCard.height,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HomeCollectionCard.corner)
                .strokeBorder(Color(hex: 0x48433B).opacity(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: HomeCollectionCard.corner))
    }

    private func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickCapture(trimmed)
        prompt = ""
    }
}

/// One collection card in the Home grid (handoff screen 01): 188 pt tall,
/// r26, the title in Bold 20 at (30, 26) (#D9CDBA, or AA-safe for large
/// text -- see `Style.cycle`), and a 110 x 60 art block
/// with its accent layer 18 above the bottom edge. No note count.
struct HomeCollectionCard: View {
    static let height: CGFloat = 188
    static let corner: CGFloat = 26

    /// The handoff's four card colors, cycled by grid position.
    struct Style {
        let card: Color
        let art: Color
        let accent: Color
        /// The handoff's #D9CDBA where it reads at 3:1 (forest, 8.4:1).
        var title = Color(hex: 0xD9CDBA)

        /// Accessibility deviation (decided 2026-10-15, as dev had it): the
        /// handoff's titles read at 1.5-2.5:1 on the grey, olive and tan
        /// cards, under the 3:1 that Bold 20 (large text) needs. Grey and
        /// olive keep the drawn card colors under a paper title (3.5 and
        /// 3.4:1), the tan card takes an ink title (7:1).
        static func cycle(_ index: Int) -> Style {
            let warmAccent = Color(hex: 0x8F7E76).opacity(0.5)
            let coolAccent = Color(hex: 0xEEF1EB).opacity(0.32)
            switch index % 4 {
            case 1: return Style(card: Palette.forest, art: Color(hex: 0xB6C2BA), accent: coolAccent)
            case 2: return Style(card: Color(hex: 0x878476), art: Palette.forest, accent: warmAccent,
                                 title: Palette.onInk)
            case 3: return Style(card: Color(hex: 0xC1A47E), art: Color(hex: 0xC1A47E), accent: coolAccent,
                                 title: Palette.ink)
            default: return Style(card: Color(hex: 0x8F7E76), art: Color(hex: 0xD6BFAA), accent: warmAccent,
                                  title: Palette.onInk)
            }
        }
    }

    let title: String
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Sans.font(size: 22, weight: 700))
                .foregroundStyle(style.title)
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .frame(width: 118, alignment: .leading)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 18)
                .fill(style.art)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(style.accent))
                .frame(width: 110, height: 60)
        }
        .padding(.top, 27)
        .padding(.leading, 30)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(style.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.corner)
                        .strokeBorder(Color(hex: 0x48433B).opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x544738).opacity(0.1), radius: 17, y: 18)
        )
    }
}

extension HomeView {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = format
        return formatter
    }

    private static let weekdayFormatter = formatter("EEEE,")
    private static let dayFormatter = formatter("MMMM d")

    /// The editorial dateline: "MONDAY," over "JUNE 22". Pinned to English
    /// -- all of the app's copy is.
    static func dateLines(for date: Date) -> (weekday: String, day: String) {
        (weekdayFormatter.string(from: date).uppercased(), dayFormatter.string(from: date).uppercased())
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
}
