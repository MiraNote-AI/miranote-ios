import MiraNoteKit
import SwiftUI

// MARK: - The star jar

/// Home's star jar: its circle in the header, the stars it shows and a
/// saved page's star landing in it (#206). The circle and the fold over
/// Home share HomeView's fold state, so that state is internal.
extension HomeView {
    /// This month's stars, as the jar shows them, each in its page's dress
    /// once it is baked.
    var jarPile: JarPile {
        // Read here so that each dress Home bakes redraws the jar with it.
        _ = dressesBaked
        return JarPile(jarStars.map(\.id))
    }

    private var jarStars: [JarStar] {
        StarJar.stars(in: viewModel.library, during: JarPeriod.month.interval(containing: .now))
    }

    /// When Home looks for dresses its jar is missing: for this month's
    /// jar, and again once a star has landed. A star on its way keeps the
    /// dress its fold cut (`StarFace.keep` as it lands), so Home bakes
    /// nothing meanwhile.
    struct DressRound: Equatable {
        let month: Date
        let arriving: Memory.ID?
    }

    var dressRound: DressRound {
        DressRound(month: JarPeriod.month.interval(containing: .now).start, arriving: arrivingStar?.id)
    }

    /// Bakes the dresses this month's stars are missing -- pages saved
    /// before design X's dresses (#234), or whose dress iOS cleared from
    /// Caches -- as the jar screen's stars do: `StarFace.bakeInTurn`, one
    /// at a time a frame apart, into the same cache. The header jar shows
    /// each one as it is baked, with no visit to the jar screen (#243).
    func dressTheJar() async {
        guard arrivingStar == nil else { return }
        for star in jarStars where StarFace.cached(star.id) == nil {
            if Task.isCancelled { return }
            if await StarFace.bakeInTurn(star.memory) != nil { dressesBaked += 1 }
        }
    }

    /// The star jar's circle: the glass jar, small, with this month's
    /// stars (design X). While a Save folds, the fold draws it.
    var headerJar: some View {
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
    /// which fades out where it is as it fades into the jar (0.5 s).
    /// Haptics on the fold's beats. Home scrolls to its top at once, under
    /// the fold: the jar chip scrolls with the page.
    func landArrivingStar(_ scroller: ScrollViewProxy) async {
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
    func finishFold() {
        guard let start = foldStart else { return }
        let land = foldFades ? StarFold.fadeEnd : StarFold.land
        if StarClock.ms(since: start) < land { landed() }
        foldStart = nil
        onStarLanded()
    }
}
