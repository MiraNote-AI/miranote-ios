import MiraNoteKit
import SwiftUI
import UIKit

// MARK: - Open

/// The star jar's open (#206): a held star unfolds back into its page,
/// which then opens. Kept apart from StarJarView.swift, whose state it
/// shares.
extension StarJarView {
    /// A star unfolding into its page.
    struct Opening {
        let star: JarStar
        let paper: StarPaper
        /// The held star's middle on screen, its radius and turn.
        let from: CGPoint
        let radius: CGFloat
        let rotation: Double
        /// The jar's frame on screen: its cap comes off.
        let jar: CGRect
        let start: Date
        /// The reading page has taken over.
        var opened = false
    }

    /// In the air, unfolding: unseen. While another star is held: dimmed.
    func opacity(of star: JarStar) -> Double {
        if tossing || opening?.star.id == star.id { return 0 }
        return holding != nil && holding != star.id ? 0.35 : 1
    }

    /// A hold gathering on `star` dims the rest, and readies its page to
    /// unfold; a hold let go springs them back.
    func tension(_ on: Bool, on star: JarStar) {
        guard on else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { holding = nil }
            held = nil
            return
        }
        // Another finger's hold, once a star is opening: nothing to dim.
        guard opening == nil, openTask == nil else { return }
        withAnimation(.linear(duration: StarHold.commitAfter - StarHold.tapWindow)) { holding = star.id }
        guard held?.id != star.id else { return }
        Task { @MainActor in
            guard let paper = await StarFace.paper(for: star.memory) else { return }
            if holding == star.id { held = (star.id, paper) }
        }
    }

    /// The hold committed: the star unfolds into its page (`StarUnfold`),
    /// which reading mode then shows where the unfold left it; under
    /// Reduce Motion the page cross-fades in.
    func open(_ star: JarStar, from point: CGPoint, size: CGFloat, rotation: Double) {
        guard opening == nil, openTask == nil else { return }
        let ready = held?.id == star.id ? held?.paper : nil
        holding = nil
        held = nil
        openTask = Task { @MainActor in
            // Usually readied while the hold gathered; else now.
            let paper: StarPaper? = if let ready { ready } else { await StarFace.paper(for: star.memory) }
            guard !Task.isCancelled else { return }
            guard let paper else {
                opened(star, .push)
                return
            }
            let start = Date.now
            opening = Opening(star: star, paper: paper, from: point, radius: size * 0.45, rotation: rotation,
                              jar: jarFrame, start: start)
            // A cancel (the jar left meanwhile) stops it before the page opens.
            do {
                if reduceMotion {
                    withAnimation(.linear(duration: StarUnfold.fade / 1000)) { jarFade = 0 }
                    try await Task.sleep(for: .milliseconds(Int(StarUnfold.fade)))
                    opened(star, .instant)
                    return
                }
                // The jar fades and sinks as the star leaves it.
                withAnimation(.easeInOut(duration: 0.31 * StarClock.rate).delay(0.25 * StarClock.rate)) {
                    jarFade = 0
                    jarSink = 30
                }
                let haptics = StarHaptics()
                for haptic in StarUnfold.haptics.dropFirst() where haptic.ms < StarUnfold.end {
                    try await sleep(until: haptic.ms, from: start)
                    haptics.play(haptic)
                }
                try await sleep(until: StarUnfold.end, from: start)
                if let last = StarUnfold.haptics.last, last.ms >= StarUnfold.end { haptics.play(last) }
                opened(star, .instant)
            } catch {
                return
            }
        }
    }

    private func sleep(until ms: Double, from start: Date) async throws {
        try await StarClock.sleep(until: ms, from: start)
    }

    private func opened(_ star: JarStar, _ style: OpenStyle) {
        openTask = nil
        opening?.opened = true
        hasOpened = true
        onOpenNote(star, style)
    }

    /// Back from the page: the jar comes back. No refold.
    func cameBack() {
        guard opening != nil else { return }
        holding = nil
        held = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.3)) {
                jarFade = 1
                jarSink = 0
                opening = nil
            }
        }
    }

    /// The unfold over the jar. It takes every touch while it plays.
    @ViewBuilder var unfolding: some View {
        if let opening, !opening.opened {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                OpenUnfold(paper: opening.paper,
                           from: CGPoint(x: opening.from.x - origin.x, y: opening.from.y - origin.y),
                           radius: opening.radius, rotation: opening.rotation,
                           jar: opening.jar.offsetBy(dx: -origin.x, dy: -origin.y), start: opening.start,
                           reduceMotion: reduceMotion)
                Color.clear.contentShape(Rectangle())
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
