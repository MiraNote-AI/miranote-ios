import MiraNoteKit
import SwiftUI

/// The star jar (team decision 2026-10-24, no design screen): every saved
/// page is a star colored by its mood, a week or a month to a jar. Drawn
/// in the app's own language -- paper, hairlines, quiet type. Its one
/// motion: pages saved since the jar was last opened drop in.
struct StarJarView: View {
    var viewModel: HomeViewModel
    var onBack: () -> Void = {}
    var onOpenNote: (JarStar) -> Void = { _ in }
    /// The shown pages, to ask the mood of one at a time: the judge skips
    /// one judged from its current words, and asks again one whose words
    /// changed after an ask at Save failed -- unless it is a draft, which
    /// waits for its next Save (#137). `[]` when the jar closes.
    var onShow: ([Memory.ID]) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var period: JarPeriod = .month
    @State private var interval = JarPeriod.month.interval(containing: .now)
    /// Stars dropping in on this visit, in drop order; set once.
    @State private var arriving: [Memory.ID] = []
    @State private var visited = false
    @State private var viewport: CGFloat = 0

    /// When the jar was last opened: what was saved since drops in.
    static let lastOpenedKey = "starJar.lastOpened"

    private var stars: [JarStar] {
        StarJar.stars(in: viewModel.library, during: interval)
    }

    private var isCurrent: Bool { interval.contains(.now) }

    /// Past the current period only while a later one holds stars: a page
    /// can be dated ahead, and must stay reachable.
    private var canStepForward: Bool {
        interval.end <= .now || StarJar.hasStars(in: viewModel.library, from: interval.end)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                periodPicker
                    .padding(.bottom, 10)
                periodStepper
                    .padding(.bottom, 14)
                jar
                    .padding(.bottom, 18)
                // An empty jar says so inside it.
                if !stars.isEmpty {
                    Text(summary)
                        .font(Sans.font(size: 16, weight: 600))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("jar.summary")
                        .padding(.bottom, 14)
                }
                legend
            }
            .padding(.horizontal, Metrics.chromeInset)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        .screenBackground()
        .safeAreaInset(edge: .top) { header }
        .onAppear(perform: firstVisit)
        .task(id: interval) {
            onShow(stars.map(\.id))
        }
        .onDisappear { onShow([]) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Home")
                }
            }
            .buttonStyle(SoftPill())
            Spacer()
            Text("Star jar")
                .font(.miraScreenTitle)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 8)
        .background(theme.background.opacity(0.94))
    }

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(JarPeriod.allCases, id: \.self) { option in
                Button(option == .week ? "Week" as LocalizedStringKey : "Month") {
                    period = option
                    interval = option.interval(containing: isCurrent ? .now : interval.start)
                }
                .buttonStyle(SoftPill(selected: option == period, theme: theme))
                .accessibilityAddTraits(option == period ? .isSelected : [])
                .accessibilityIdentifier("jar.period.\(option.rawValue)")
            }
        }
    }

    private var periodStepper: some View {
        HStack {
            let previous = period == .week ? String(appCopy: "Previous week") : String(appCopy: "Previous month")
            stepButton("chevron.left", label: previous, id: "jar.previous") {
                interval = period.interval(shifting: interval, by: -1)
            }
            Spacer()
            Text(period.label(for: interval, locale: AppSettings.shared.language.locale))
                .font(.miraCardTitle)
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("jar.period")
            Spacer()
            let next = period == .week ? String(appCopy: "Next week") : String(appCopy: "Next month")
            stepButton("chevron.right", label: next, id: "jar.next") {
                interval = period.interval(shifting: interval, by: 1)
            }
            .disabled(!canStepForward)
            // On Forest's dark green a fainter paper circle loses its arrow.
            .opacity(canStepForward ? 1 : (theme.appearance == .forest ? 0.5 : 0.35))
        }
    }

    /// The 34 pt paper circle of reading mode's buttons, hit-tested at 44.
    private func stepButton(
        _ symbol: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Palette.onInk)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: The jar

    private var jar: some View {
        GeometryReader { proxy in
            let geometry = JarGeometry(size: proxy.size)
            let pile = StarPile.layout(stars.map(\.id), in: geometry.interior)
            ZStack(alignment: .topLeading) {
                JarGlass(geometry: geometry)
                // After the visit has decided what drops in.
                ForEach(Array((visited ? stars : []).enumerated()), id: \.element.id) { index, star in
                    let spot = pile.spots[index]
                    StarButton(
                        star: star,
                        size: pile.starSize,
                        rotation: spot.rotation,
                        drop: dropOffset(for: star.id, at: spot.center, geometry: geometry),
                        delay: dropDelay(for: star.id),
                        reduceMotion: reduceMotion
                    ) {
                        onOpenNote(star)
                    }
                    .position(spot.center)
                }
                JarShine(geometry: geometry)
                JarLid(geometry: geometry)
                if stars.isEmpty {
                    Text(emptyLine)
                        .font(.miraBody)
                        .foregroundStyle(theme.muted(Palette.textSecondary))
                        .multilineTextAlignment(.center)
                        .frame(width: geometry.interior.width - 80)
                        .accessibilityIdentifier("jar.empty")
                        .position(x: geometry.interior.midX, y: geometry.interior.midY + 20)
                }
            }
            // Small stars hit-test at 1.3x: a tap between them opens the
            // nearest within 17 pt, so even a crowd keeps a 34 pt target
            // without one star covering another.
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard visited else { return }
                let nearest = zip(stars, pile.spots)
                    .map { (star: $0, distance: hypot($1.center.x - point.x, $1.center.y - point.y)) }
                    .min { $0.distance < $1.distance }
                if let nearest, nearest.distance <= 17 { onOpenNote(nearest.star) }
            }
        }
        .aspectRatio(JarGeometry.aspect, contentMode: .fit)
        // As wide as fits, short enough that the count and legend stay on
        // screen on a small phone (the rest of the column is ~290 pt).
        .frame(maxWidth: min(320, max(220, (viewport - 290) * JarGeometry.aspect)))
    }

    private var emptyLine: String {
        switch (period, isCurrent) {
        case (.week, true): return String(appCopy: "No memories yet this week.")
        case (.month, true): return String(appCopy: "No memories yet this month.")
        case (.week, false): return String(appCopy: "No memories that week.")
        case (.month, false): return String(appCopy: "No memories that month.")
        }
    }

    private var summary: String {
        let count = stars.count
        switch (period, isCurrent) {
        case (.week, true): return String(appCopy: "\(count) memories this week")
        case (.month, true): return String(appCopy: "\(count) memories this month")
        case (.week, false): return String(appCopy: "\(count) memories that week")
        case (.month, false): return String(appCopy: "\(count) memories that month")
        }
    }

    private var legend: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
            ForEach(Mood.allCases, id: \.self) { mood in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Palette.mood(mood))
                        .frame(width: 10, height: 10)
                        // The name alone is the element: framed with the
                        // dot, the contrast audit read the grey text against
                        // the light Calm and Low dots (6.1:1 on the paper).
                        .accessibilityHidden(true)
                    Text(mood.displayName)
                        .font(.miraCaption)
                        .foregroundStyle(theme.muted(Palette.textSecondary))
                }
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: Arrivals

    /// Once per visit: what was saved since the jar was last opened drops
    /// in. A first visit drops the whole period once.
    private func firstVisit() {
        guard !visited else { return }
        visited = true
        let defaults = UserDefaults.standard
        let lastOpened = defaults.object(forKey: Self.lastOpenedKey) as? Date
        defaults.set(Date.now, forKey: Self.lastOpenedKey)
        arriving = stars
            .filter { star in
                guard let lastOpened else { return true }
                return (star.memory.savedAt ?? star.memory.createdAt) > lastOpened
            }
            .map(\.id)
        // Landed: a later switch of period shows these at rest.
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            arriving = []
        }
    }

    private func dropOffset(for id: Memory.ID, at center: CGPoint, geometry: JarGeometry) -> CGSize? {
        guard arriving.contains(id) else { return nil }
        // From the middle of the mouth, a little apart from each other.
        let spread = CGFloat(StarPile.unit(id, 7) - 0.5) * geometry.mouthWidth * 0.5
        return CGSize(width: geometry.size.width / 2 + spread - center.x, height: geometry.mouthY - center.y)
    }

    /// Staggered 0.08 s, squeezed so the last starts within 0.9 s.
    private func dropDelay(for id: Memory.ID) -> Double {
        guard let index = arriving.firstIndex(of: id) else { return 0 }
        let stagger = min(0.08, 0.9 / Double(max(1, arriving.count - 1)))
        return Double(index) * stagger
    }
}

// MARK: - Star

/// One star: a tap opens its page. It drops in from `drop` when given one
/// (or, under Reduce Motion, fades in), and its mood tints it with a short
/// cross-fade when the mood arrives.
private struct StarButton: View {
    let star: JarStar
    let size: CGFloat
    let rotation: Double
    let drop: CGSize?
    let delay: Double
    let reduceMotion: Bool
    let action: () -> Void

    @State private var landed = false

    var body: some View {
        let waiting = drop != nil && !landed
        Button(action: action) {
            StarMark(color: Palette.mood(star.memory.mood))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(waiting && !reduceMotion ? 0 : rotation))
                .frame(width: size * 1.3, height: size * 1.3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
        .opacity(waiting ? 0 : 1)
        .animation(.easeInOut(duration: 0.6), value: star.memory.mood)
        .onAppear {
            guard drop != nil, !landed else { return }
            let motion: Animation = reduceMotion
                ? .easeOut(duration: 0.4)
                : .spring(response: 0.55, dampingFraction: 0.68)
            withAnimation(motion.delay(delay)) { landed = true }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    private var accessibilityText: String {
        let title = star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
        return String(appCopy: "\(title), \(star.memory.mood?.displayName ?? String(appCopy: "mood not read yet"))")
    }
}

/// The star's face: the mood's fill, a soft light from above, and a
/// hairline edge so neighbors in a pile stay apart.
private struct StarMark: View {
    let color: Color

    var body: some View {
        RoundedStar()
            .fill(color)
            .overlay(
                RoundedStar().fill(
                    LinearGradient(colors: [Color.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                )
            )
            .overlay(RoundedStar().stroke(Palette.ink.opacity(0.1), lineWidth: 0.6))
    }
}

/// A five-point star with softened tips.
struct RoundedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.5
        let points: [CGPoint] = (0..<10).map { index in
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 5
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        func toward(_ from: CGPoint, _ to: CGPoint, _ share: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
        }
        var path = Path()
        for index in 0..<10 {
            let point = points[index]
            let previous = points[(index + 9) % 10]
            let next = points[(index + 1) % 10]
            let share: CGFloat = index.isMultiple(of: 2) ? 0.24 : 0.12
            let start = toward(point, previous, share)
            if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: toward(point, next, share), control: point)
        }
        path.closeSubpath()
        return path
    }
}
