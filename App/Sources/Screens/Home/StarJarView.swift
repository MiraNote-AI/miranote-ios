import MiraNoteKit
import SpriteKit
import SwiftUI

/// The star jar (team decision 2026-10-24, no design screen): every saved
/// page is a star made of a strip of the page (#206), a week or a month to
/// a jar. Drawn in the app's own language -- paper, hairlines, quiet type.
/// Its motion: pages saved since the jar was last opened drop in, and a
/// tap anywhere on the jar shakes it, tossing the stars up like popcorn.
/// Holding a star opens its page.
struct StarJarView: View {
    var viewModel: HomeViewModel
    var onBack: () -> Void = {}
    var onOpenNote: (JarStar) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.theme) private var theme
    @State private var period: JarPeriod = .month
    @State private var interval = JarPeriod.month.interval(containing: .now)
    /// Stars dropping in on this visit, in drop order; set once.
    @State private var arriving: [Memory.ID] = []
    @State private var visited = false
    @State private var viewport: CGFloat = 0
    /// Taps on the jar so far: each one shakes it.
    @State private var shakes = 0
    /// The shakes that threw the stars (none under Reduce Motion).
    @State private var tosses = 0
    /// Stars in the air: drawn by `tossScene`, their buttons hidden.
    @State private var tossing = false
    @State private var tossScene = StarTossScene(size: .zero)
    /// Where the last toss left each star, until the visit ends.
    @State private var settled: [Memory.ID: StarPile.Spot] = [:]

    /// When the jar was last opened: what was saved since drops in.
    static let lastOpenedKey = "starJar.lastOpened"

    private var stars: [JarStar] {
        StarJar.stars(in: viewModel.library, during: interval)
    }

    private var isCurrent: Bool { interval.contains(.now) }

    /// `-REDUCE_MOTION` stands in for the setting in UI tests.
    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-REDUCE_MOTION") { return true }
        #endif
        return systemReduceMotion
    }

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
                Text("Tap to shake. Hold a star to open.")
                    .font(.miraCaption)
                    .foregroundStyle(theme.muted(Palette.textSecondary))
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.chromeInset)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        #if DEBUG
        .background(DebugStateProbe {
            ["scene": "jar", "shakes": shakes, "tosses": tosses, "settled": !tossing,
             "tossFPS": tossScene.frameStats.fps, "tossWorstMs": tossScene.frameStats.worstMs]
        })
        #endif
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        .screenBackground()
        .safeAreaInset(edge: .top) { header }
        .onAppear(perform: firstVisit)
        .onChange(of: interval) {
            tossScene.stop()
            settled = [:]
        }
        .onDisappear {
            // Opened mid-air: the stars lie where they did before the toss.
            tossScene.stop()
        }
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
            let spots = zip(stars, pile.spots).map { settled[$0.id] ?? $1 }
            ZStack(alignment: .topLeading) {
                JarGlass(geometry: geometry)
                // After the visit has decided what drops in.
                ForEach(Array((visited ? stars : []).enumerated()), id: \.element.id) { index, star in
                    let spot = spots[index]
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
                    // VoiceOver shakes the jar from any of its stars.
                    .accessibilityAction(named: Text("Shake")) {
                        shake(Array(zip(stars, spots)), starSize: pile.starSize, geometry: geometry)
                    }
                    .position(spot.center)
                    .opacity(tossing ? 0 : 1)
                    // A hold is ignored while the stars are in the air.
                    .allowsHitTesting(!tossing)
                }
                SpriteView(scene: tossScene, isPaused: !tossing, options: [.allowsTransparency])
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(tossing ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
            // A tap anywhere, on a star too, shakes (#206): only a hold
            // opens one, so a crowd never makes the toss unreachable.
            .contentShape(Rectangle())
            .onTapGesture {
                guard visited else { return }
                shake(Array(zip(stars, spots)), starSize: pile.starSize, geometry: geometry)
            }

            .onChange(of: proxy.size) { settled = [:] }
            // A shake: pressed down, a small hop, a sway or two from the
            // foot. Under Reduce Motion only a small sway.
            .keyframeAnimator(initialValue: JarPose(), trigger: shakes) { content, pose in
                content
                    .rotationEffect(.degrees(pose.angle), anchor: .bottom)
                    .offset(y: pose.lift)
            } keyframes: { _ in
                KeyframeTrack(\.lift) {
                    if reduceMotion {
                        LinearKeyframe(0, duration: 0.01)
                    } else {
                        SpringKeyframe(5, duration: 0.08)
                        SpringKeyframe(-7, duration: 0.14)
                        SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                    }
                }
                KeyframeTrack(\.angle) {
                    if reduceMotion {
                        SpringKeyframe(-1.5, duration: 0.15)
                        SpringKeyframe(1, duration: 0.2)
                        SpringKeyframe(0, duration: 0.3)
                    } else {
                        LinearKeyframe(0, duration: 0.08)
                        SpringKeyframe(-3.5, duration: 0.14)
                        SpringKeyframe(2.5, duration: 0.18)
                        SpringKeyframe(-1, duration: 0.18)
                        SpringKeyframe(0, duration: 0.3)
                    }
                }
            }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: shakes)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("jar.glass")
        }
        .aspectRatio(JarGeometry.aspect, contentMode: .fit)
        // As wide as fits, short enough that the count and hint stay on
        // screen on a small phone (the rest of the column is ~290 pt).
        .frame(maxWidth: min(320, max(220, (viewport - 290) * JarGeometry.aspect)))
    }

}

// MARK: - Toss and words

extension StarJarView {
    /// A shake of the jar: it sways, and the stars fly up.
    private func shake(
        _ resting: [(star: JarStar, spot: StarPile.Spot)], starSize: CGFloat, geometry: JarGeometry
    ) {
        shakes += 1
        throwStars(resting, starSize: starSize, geometry: geometry)
    }

    /// Throws the stars up from where they lie, or adds to a toss in the
    /// air. Not under Reduce Motion, nor while stars are still dropping in.
    private func throwStars(
        _ resting: [(star: JarStar, spot: StarPile.Spot)], starSize: CGFloat, geometry: JarGeometry
    ) {
        guard !reduceMotion, arriving.isEmpty, !resting.isEmpty else { return }
        if !tossing {
            tossScene.load(resting, starSize: starSize, geometry: geometry) { star in
                StarTossScene.face(of: star.memory)
            }
            tossScene.onSettle = { [landed = $settled, inAir = $tossing] spots in
                landed.wrappedValue = spots
                inAir.wrappedValue = false
            }
            tossing = true
        }
        tosses += 1
        tossScene.toss()
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

}

// MARK: - Arrivals

extension StarJarView {
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
