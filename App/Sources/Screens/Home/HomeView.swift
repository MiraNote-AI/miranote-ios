import MiraNoteKit
import SwiftUI

/// Handoff screen 01: the wordmark row with the profile circle, the
/// two-line dateline, the editorial hero, the ink "Start a memory" button,
/// the retrieval prompt bar, and the collection grid -- driven by the
/// user's real, persisted note collections. Beyond the design: a "New
/// collection" card closes the grid and "Recently deleted" sits under it
/// when the bin holds anything. Forest and Sunlit Pop redraw it in their
/// colors and type (handoff 2026-10-24, screens 01-02; see `Theme`).
struct HomeView: View {
    var viewModel: HomeViewModel
    var onStart: () -> Void = {}
    /// The ask bar: opens the Mira chat.
    var onAsk: () -> Void = {}
    var onOpenCollection: (MemoryCollection) -> Void = { _ in }
    var onOpenTrash: () -> Void = {}
    var onOpenStarJar: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenProfile: () -> Void = {}
    /// The photo trigger's debug entry, at the foot of the page; nil hides it.
    var triggerEntry: TriggerDebugEntry?
    /// A page Save just made a star: it lands in the jar.
    var arrivingStar: Memory?
    /// Its page ready to fold (#206), or under Reduce Motion to fade into
    /// its star; nil if it could not be drawn: the jar only takes it in.
    var arrivingFold: StarPaper?
    /// The star is in: the fold has played or a tap or leaving cut it short.
    var onStarLanded: () -> Void = {}

    @Environment(\.theme) private var theme
    @State private var addingCollection = false
    @State private var newCollectionName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// When the fold started; nil when none is playing.
    @State private var foldStart: Date?
    /// The fold is the Reduce Motion fade: kept from its start.
    @State private var foldFades = false
    /// Landings so far (UI tests count them).
    @State private var jarBeat = 0

    /// The dateline's warm grey (#8F8477), also used for the extras the
    /// design does not draw (New collection, Recently deleted).
    static let dateColor = Color(hex: 0x8F8477)

    /// The top of the page, to scroll back to.
    private static let top = "home.top"

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(showsIndicators: false) {
                // Vertical rhythm from the handoff's frames, in Josefin's 1.0 em
                // line boxes (the CSS 1.18 line height adds its half-leading to
                // the gaps here).
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .id(Self.top)
                        .padding(.bottom, 8)
                    dateline
                        .padding(.bottom, 9 + theme.heroGaps.above)
                    hero
                        .padding(.bottom, 28 + theme.heroGaps.below)
                    startButton
                        .padding(.bottom, 27)
                    promptBar
                        .anchorPreference(key: JarAnchorKey.self, value: .bounds) { .init(askBar: $0) }
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
                            .foregroundStyle(theme.muted(Palette.textSecondary))
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.trash")
                        .padding(.top, 8)
                    }

                    if let triggerEntry {
                        triggerEntry
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, Metrics.chromeInset)
                // The profile circle rises 6 pt into the status-bar band: the
                // wordmark, not the circle, lines up with the editor's nav row.
                .padding(.top, -6)
                .padding(.bottom, 28)
            }
            .task(id: arrivingStar?.id) { await landArrivingStar(scroller) }
        }
        // A tap during the fold skips to the landing, and still does what
        // it tapped (the jar opens, a page starts).
        .simultaneousGesture(TapGesture().onEnded { finishFold() })
        .overlayPreferenceValue(JarAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let foldStart, let arrivingFold, let arrivingStar, let jar = anchors.jar {
                    SaveFold(paper: arrivingFold, chip: proxy[jar], clear: anchors.askBar.map { proxy[$0].maxY } ?? 0,
                             pile: jarPile, newStar: arrivingStar.id,
                             start: foldStart, editorBackground: Theme(appearance: .system).background,
                             veilColor: theme.background, reduceMotion: foldFades)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active, foldStart != nil { finishFold() }
        }
        .screenBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.root")
        #if DEBUG
        // UI tests read the theme Home is drawn in (VoiceOver users of a
        // release build are not read it).
        .accessibilityValue(theme.appearance.rawValue)
        #endif
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

    /// Wordmark (Bold 15, #25231F), then the 38 pt glass settings and
    /// profile circles, 8 apart (handoff 2026-10-24, screens 01-02). The
    /// 2026-10-07 design's bell is left out: nothing stands behind it yet.
    private var header: some View {
        HStack(alignment: .top) {
            Text("MiraNote")
                .font(theme.wordmark.font)
                .foregroundStyle(theme.wordmark.color)
                .padding(.top, 9)
            Spacer()
            HStack(spacing: 8) {
                // Not drawn by the handoff: the star jar, a twin of the
                // circles beside it.
                headerJar
                    .anchorPreference(key: JarAnchorKey.self, value: .center) { .init(jar: $0) }
                    #if DEBUG
                    // UI tests count the landings.
                    .accessibilityValue("\(jarBeat)")
                    #endif
                headerCircle("home.settings", label: "Settings", action: onOpenSettings)
                headerCircle("home.profile", label: "Profile", action: onOpenProfile)
            }
        }
    }

    /// This month's stars, as the jar shows them.
    private var jarPile: JarPile {
        JarPile(StarJar.stars(in: viewModel.library, during: JarPeriod.month.interval(containing: .now)).map(\.id))
    }

    /// The star jar's circle: the glass jar, small, with this month's
    /// stars (design X). While a Save folds, the fold draws it.
    private var headerJar: some View {
        Button(action: onOpenStarJar) {
            HeaderJar(pile: jarPile)
                .frame(width: 30, height: 30)
                .opacity(foldStart == nil ? 1 : 0)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .circleHitTarget()
        .accessibilityLabel("Star jar")
        .accessibilityIdentifier("home.starJar")
    }

    /// The page folds into its star over Home and drops into the jar
    /// (`SaveFold`, 1.8 s); under Reduce Motion it cross-fades to its star,
    /// which fades into the jar (0.5 s). Haptics on the fold's beats. Home
    /// scrolls to its top at once, under the fold: the jar chip scrolls
    /// with the page.
    private func landArrivingStar(_ scroller: ScrollViewProxy) async {
        guard arrivingStar != nil else { return }
        scroller.scrollTo(Self.top, anchor: .top)
        do {
            if arrivingFold != nil {
                let start = Date.now
                let fades = ReduceMotion.resolved(reduceMotion)
                let haptics = fades ? StarFold.fadeHaptics : StarFold.haptics
                let land = fades ? StarFold.fadeEnd : StarFold.land, end = fades ? StarFold.fadeEnd : StarFold.end
                let generators = StarHaptics()
                foldFades = fades
                foldStart = start
                // A tap may finish the fold before this task is cancelled.
                func wait(until ms: Double) async throws {
                    try await sleep(until: ms, from: start)
                    if foldStart != start { throw CancellationError() }
                }
                var landedYet = false
                for haptic in haptics {
                    if !landedYet, haptic.ms >= land {
                        try await wait(until: land)
                        landedYet = true
                        landed()
                    }
                    try await wait(until: haptic.ms)
                    generators.play(haptic)
                }
                if !landedYet {
                    try await wait(until: land)
                    landed()
                }
                try await wait(until: end)
                foldStart = nil
            } else {
                try await Task.sleep(for: .milliseconds(450))
                landed()
                try await Task.sleep(for: .milliseconds(800))
            }
        } catch {
            // Cut short: by a tap or the app leaving (`finishFold` has
            // run), or by Home leaving with no tap on it mid-fold (a
            // VoiceOver activation opens the jar), which cancels this
            // task. Then the star is in at once, as when the app leaves,
            // and the fold does not play again when Home is back.
            finishFold()
            return
        }
        onStarLanded()
    }

    /// The jar takes the star in; VoiceOver, which sees none of the fold,
    /// hears it.
    private func landed() {
        jarBeat += 1
        AccessibilityNotification.Announcement(String(appCopy: "Saved to your star jar")).post()
    }

    private func sleep(until ms: Double, from start: Date) async throws {
        try await StarClock.sleep(until: ms, from: start)
    }

    /// A tap, or the app leaving the front, during the fold: the star is
    /// in the jar at once.
    private func finishFold() {
        guard let start = foldStart else { return }
        let land = foldFades ? StarFold.fadeEnd : StarFold.land
        if StarClock.ms(since: start) < land { landed() }
        foldStart = nil
        onStarLanded()
    }

    private func headerCircle(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.homeIcon)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .circleHitTarget()
        .accessibilityLabel(label)
        .accessibilityIdentifier(icon)
    }

    /// "MONDAY," over an indented "JUNE 22", Josefin Bold 24 in #8F8477.
    private var dateline: some View {
        let lines = HomeView.dateLines(for: .now)
        let style = theme.dateline
        return VStack(alignment: .leading, spacing: style.lineSpacing) {
            Text(lines.weekday)
            Text(lines.day)
                .padding(.leading, theme.datelineIndent)
        }
        .font(style.font)
        .foregroundStyle(style.color)
        .accessibilityElement(children: .combine)
    }

    /// Two lines at the design's 1.02 line height: Fraunces' own line box
    /// is ~7 pt taller than 1769_W05's, so the lines overlap by that much.
    private var hero: some View {
        let style = theme.hero
        return VStack(spacing: style.lineSpacing) {
            Text("Your memory,")
            Text("beautifully made.")
        }
        .font(style.font)
        .foregroundStyle(style.color)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The handoff's 226 x 92 pt ink button with a long warm shadow.
    private var startButton: some View {
        Button(action: onStart) {
            Text("Start a memory")
                .font(theme.startLabelFont)
                .foregroundStyle(theme.startLabel)
                // One line: the button is drawn 226 wide.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
                .frame(width: 226, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 36)
                        .fill(theme.button)
                        .shadow(color: Color(hex: 0x544738).opacity(0.16), radius: 28, y: 30)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("Start a memory")
    }

    /// The 41 pt retrieval bar: the four-point star in a 26 pt #C6B298
    /// circle, then the Bold 16 question at ink@0.5. A tap anywhere on it
    /// opens the Mira chat with the chat's field focused; it never starts
    /// a note.
    private var promptBar: some View {
        HStack(spacing: 12) {
            Image("home.spark")
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.homeIcon)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.promptIconFill))

            Text("When was my Paris trip?")
                .font(theme.promptFont)
                .foregroundStyle(theme.promptPlaceholder)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: 41)
        .background(
            Capsule()
                .fill(theme.promptFill)
                .shadow(color: Color(hex: 0x544738).opacity(0.08), radius: 16, y: 16)
        )
        .contentShape(Capsule())
        // A tap, not a Button: an edge swipe across Home ended on the bar
        // as a Button and opened the chat (SwipeBackUITests).
        .onTapGesture(perform: onAsk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ask Mira")
        // Voice Control: the words on the bar work too.
        .accessibilityInputLabels([Text("Ask Mira"), Text("When was my Paris trip?")])
        .accessibilityHint("Opens the Mira chat")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAsk() }
        .accessibilityIdentifier("home.ask")
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
                    HomeCollectionCard(title: collection.title, style: theme.card(index))
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
        .foregroundStyle(theme.muted(Self.dateColor))
        .padding(.top, 26)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, minHeight: HomeCollectionCard.height, maxHeight: HomeCollectionCard.height,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HomeCollectionCard.corner)
                .strokeBorder(theme.muted(Color(hex: 0x48433B)).opacity(0.24),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: HomeCollectionCard.corner))
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
        var border = Color(hex: 0x48433B).opacity(0.12)

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

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleText
                .foregroundStyle(style.title)
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
                        .strokeBorder(style.border, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x544738).opacity(0.1), radius: 17, y: 18)
        )
    }

    /// Up to two lines, in Josefin or the theme's face.
    @ViewBuilder private var titleText: some View {
        if let face = theme.cardTitleFace {
            ThemedCardTitle(title: title, face: face, width: 118)
        } else {
            Text(title)
                .font(Sans.font(size: 22, weight: 700))
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
    }
}

extension HomeView {
    /// The editorial dateline: "MONDAY," over "JUNE 22", in the app's
    /// language (Chinese drops the comma).
    static func dateLines(for date: Date) -> (weekday: String, day: String) {
        let weekday = AppDateFormat.string(from: date, template: "EEEE")
        return (String(appCopy: "\(weekday),").uppercased(),
                AppDateFormat.string(from: date, template: "MMMMd").uppercased())
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
}
