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
    var onQuickCapture: (String) -> Void = { _ in }
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
    @State private var prompt = ""
    /// The ask bar's keyboard: a tap on the page or a scroll lowers it.
    @FocusState private var promptFocused: Bool
    @State private var addingCollection = false
    @State private var newCollectionName = ""
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// When the fold started; nil when none is playing.
    @State var foldStart: Date?
    /// The fold is the Reduce Motion fade: kept from its start.
    @State var foldFades = false
    /// Landings so far (UI tests count them).
    @State var jarBeat = 0

    /// The dateline's warm grey (#8F8477), also used for the extras the
    /// design does not draw (New collection, Recently deleted).
    static let dateColor = Color(hex: 0x8F8477)

    /// The top of the page, to scroll back to.
    static let top = "home.top"

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
                // A tap that no button takes lowers the ask bar's keyboard; the
                // words stay in the bar.
                .contentShape(Rectangle())
                .onTapGesture { promptFocused = false }
            }
            .scrollDismissesKeyboard(.immediately)
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
    /// circle, then a Bold 16 field at ink@0.5. It asks about the past and
    /// opens the Mira chat; it never starts a note.
    private var promptBar: some View {
        HStack(spacing: 12) {
            Image("home.spark")
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.homeIcon)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.promptIconFill))
                .accessibilityHidden(true)

            TextField("", text: $prompt)
                .font(theme.promptFont)
                .foregroundStyle(theme.ink)
                .tint(theme.promptTint)
                .submitLabel(.send)
                .onSubmit(submitPrompt)
                .focused($promptFocused)
                .accessibilityIdentifier("quick.field")
                .overlay(alignment: .leading) {
                    if prompt.isEmpty {
                        Text("When was my Paris trip?")
                            .font(theme.promptFont)
                            .foregroundStyle(theme.promptPlaceholder)
                            .allowsHitTesting(false)
                    }
                }

            if !prompt.isEmpty {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.ink)
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
                .fill(theme.promptFill)
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

    private func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickCapture(trimmed)
        prompt = ""
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
