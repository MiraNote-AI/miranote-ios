import MiraNoteKit
import SwiftUI

/// Where everything on the photo-trigger screen sits in each phase, in
/// full-screen coordinates. Every photo is one persistent view that moves
/// between these frames -- full screen in the story, scattered just off the
/// edges for an instant, then into its grid cell -- so the ending is one
/// continuous motion with nothing swapped in or out.
///
/// The story opens on the peak (position 0), which takes the big cell; the
/// photo on screen when the story ends shrinks into its own small cell
/// while the peak flies back into the big one (handoff 7.7).
struct TriggerStage {
    enum Phase: Equatable {
        case loading, failed, story
        /// The story is over: every photo but the one on screen has jumped,
        /// still invisible, to its starting point around the edges.
        case scatter
        /// Every photo in its cell on the card, the card centred.
        case gathered
        /// The card risen to the top, the ending's words under it.
        case settled

        var isEnding: Bool { self == .gathered || self == .settled }
    }

    struct Look {
        var rect: CGRect
        var opacity: Double
        var corner: CGFloat
        var rotation: Double
    }

    static let cardInset: CGFloat = 20
    static let cellCorner: CGFloat = 6
    static let cardCorner: CGFloat = 16
    /// Settled card's top, below the close/more row.
    static let settledTop: CGFloat = 58

    let size: CGSize
    let insets: EdgeInsets
    let count: Int
    let reduceMotion: Bool

    var full: CGRect { CGRect(origin: .zero, size: size) }

    var layout: TriggerGridLayout {
        TriggerGridLayout(photoCount: count, width: size.width - Self.cardInset * 2,
                          maxBigHeight: max(140, size.height * 0.28))
    }

    func card(settled: Bool) -> CGRect {
        let cardSize = layout.size
        let top = settled ? insets.top + Self.settledTop : (size.height - cardSize.height) / 2
        return CGRect(origin: CGPoint(x: Self.cardInset, y: top), size: cardSize)
    }

    /// The photo at story position `index` in its cell: the peak (0) in the
    /// big one, the rest in the small ones in story order.
    func cell(_ index: Int, settled: Bool) -> CGRect {
        let layout = layout
        let local = index == 0 || index > layout.small.count ? layout.big : layout.small[index - 1]
        let origin = card(settled: settled).origin
        return local.offsetBy(dx: origin.x, dy: origin.y)
    }

    func look(for index: Int, current: Int, phase: Phase) -> Look {
        switch phase {
        case .loading, .failed, .story:
            return Look(rect: full, opacity: index == current ? 1 : 0, corner: 0, rotation: 0)
        case .scatter:
            // The photo still on screen stays put, to shrink into its cell.
            if index == current { return Look(rect: full, opacity: 1, corner: 0, rotation: 0) }
            if reduceMotion {
                // No flight: they fade in where they land.
                return Look(rect: cell(index, settled: false), opacity: 0, corner: Self.cellCorner, rotation: 0)
            }
            let (rect, rotation) = scattered(index)
            return Look(rect: rect, opacity: 0, corner: Self.cellCorner, rotation: rotation)
        case .gathered, .settled:
            return Look(rect: cell(index, settled: phase == .settled), opacity: 1, corner: Self.cellCorner, rotation: 0)
        }
    }

    /// A start just past the screen's edges, as fractions of its width and
    /// height, with a tilt.
    private struct Anchor {
        let across: CGFloat
        let down: CGFloat
        let tilt: Double
    }

    private static let anchors = [
        Anchor(across: 0.5, down: -0.3, tilt: -4),
        Anchor(across: -0.16, down: 0.16, tilt: -9),
        Anchor(across: 1.16, down: 0.32, tilt: 8),
        Anchor(across: -0.18, down: 0.7, tilt: 6),
        Anchor(across: 1.18, down: 0.84, tilt: -7),
        Anchor(across: 0.22, down: 1.12, tilt: 5),
        Anchor(across: 0.82, down: -0.1, tilt: -6),
        Anchor(across: 0.58, down: 1.16, tilt: 9)
    ]

    /// A start a little larger than the cell, tilted, just off screen: the
    /// peak comes back from above, the others fly in from all round.
    private func scattered(_ index: Int) -> (CGRect, Double) {
        let anchor = Self.anchors[index % Self.anchors.count]
        let target = cell(index, settled: false)
        let width = target.width * 1.1
        let height = target.height * 1.1
        let rect = CGRect(x: anchor.across * size.width - width / 2, y: anchor.down * size.height - height / 2,
                          width: width, height: height)
        return (rect, anchor.tilt)
    }
}
