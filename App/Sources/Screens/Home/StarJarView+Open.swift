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
        let start: Date
        /// The page has unrolled: it opens from `OpenUnfold.pageFrame`.
        var unrolled = false
    }

    /// In the air, unfolding: unseen. While another star is held: dimmed.
    func opacity(of star: JarStar) -> Double {
        if tossing || opening?.star.id == star.id { return 0 }
        return holding != nil && holding != star.id ? 0.35 : 1
    }

    /// A hold gathering on `star` dims the rest, and cuts its page ready
    /// to unfold; a hold let go springs them back.
    func tension(_ on: Bool, on star: JarStar) {
        guard on else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { holding = nil }
            held = nil
            return
        }
        withAnimation(.linear(duration: StarHold.commitAfter - StarHold.tapWindow)) { holding = star.id }
        guard held?.id != star.id else { return }
        Task { @MainActor in
            guard let paper = await StarFace.paper(for: star.memory) else { return }
            if holding == star.id { held = (star.id, paper) }
        }
    }

    /// The hold committed: the star unfolds into its page, which opens
    /// (`StarUnfold`); under Reduce Motion the page fades in.
    func open(_ star: JarStar, from point: CGPoint, size: CGFloat, rotation: Double) {
        guard opening == nil, openTask == nil else { return }
        let ready = held?.id == star.id ? held?.paper : nil
        holding = nil
        held = nil
        openTask = Task { @MainActor in
            // Usually cut while the hold gathered; else cut now.
            let paper: StarPaper? = if let ready { ready } else { await StarFace.paper(for: star.memory) }
            guard !Task.isCancelled else { return }
            guard let paper else {
                opened(star, .push)
                return
            }
            let start = Date.now
            opening = Opening(star: star, paper: paper, from: point,
                              radius: size * 0.45 * (1 + StarButton.grow), rotation: rotation, start: start)
            // A cancel (the jar left meanwhile) stops it before the page opens.
            do {
                if reduceMotion {
                    withAnimation(.linear(duration: StarUnfold.fade / 1000)) { jarFade = 0 }
                    try await Task.sleep(for: .milliseconds(Int(StarUnfold.fade)))
                    opened(star, .instant)
                    return
                }
                withAnimation(.easeOut(duration: StarUnfold.riseEnd / 1000)) { jarFade = 0.25 }
                try await Task.sleep(for: .milliseconds(450))
                withAnimation(.linear(duration: 0.16)) { jarFade = 0 }
                try await sleep(until: StarUnfold.haptics[1], from: start)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                try await sleep(until: StarUnfold.unrollEnd, from: start)
                opening?.unrolled = true
                opened(star, .zoom)
            } catch {
                return
            }
        }
    }

    private func sleep(until ms: Double, from start: Date) async throws {
        let left = ms / 1000 - Date.now.timeIntervalSince(start)
        if left > 0 { try await Task.sleep(for: .seconds(left)) }
    }

    private func opened(_ star: JarStar, _ style: OpenStyle) {
        openTask = nil
        hasOpened = true
        onOpenNote(star, style)
    }

    /// Back from the page: once it has zoomed home, the jar comes back.
    /// No refold.
    func cameBack() {
        guard opening != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.3)) {
                jarFade = 1
                opening = nil
            }
        }
    }

    /// The unfold over the jar, then the unrolled page the reading view
    /// zooms from. It takes every touch while it plays.
    @ViewBuilder var unfolding: some View {
        if let opening {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                OpenUnfold(paper: opening.paper,
                           from: CGPoint(x: opening.from.x - origin.x, y: opening.from.y - origin.y),
                           radius: opening.radius, rotation: opening.rotation, start: opening.start,
                           reduceMotion: reduceMotion)
                if opening.unrolled {
                    let frame = OpenUnfold.pageFrame(opening.paper, size: proxy.size)
                    unrolledPage(opening)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
                Color.clear.contentShape(Rectangle())
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func unrolledPage(_ opening: Opening) -> some View {
        let page = opening.paper.page
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color(hex: 0x281C10).opacity(0.25), radius: 15, y: 12)
        if let zoom {
            page.zoomSource(opening.star.id, in: zoom)
        } else {
            page
        }
    }
}
