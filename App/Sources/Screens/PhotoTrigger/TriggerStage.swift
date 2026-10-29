import MiraNoteKit
import SwiftUI

/// Where everything on the photo-trigger screen sits in each phase, in
/// full-screen coordinates. Every photo is one persistent view that moves
/// between these frames -- full screen in the story, scattered just off the
/// edges for an instant, then into its grid cell -- so the ending is one
/// continuous motion with nothing swapped in or out.
struct TriggerStage {
    enum Phase: Equatable {
        case loading, failed, story
        /// The story is over: the other photos have jumped, still invisible,
        /// to their starting points around the edges.
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

    /// The photo at story position `index` (the peak is last) in its cell.
    func cell(_ index: Int, settled: Bool) -> CGRect {
        let layout = layout
        let local = index == count - 1 || index >= layout.small.count ? layout.big : layout.small[index]
        let origin = card(settled: settled).origin
        return local.offsetBy(dx: origin.x, dy: origin.y)
    }

    func look(for index: Int, current: Int, phase: Phase) -> Look {
        let isPeak = index == count - 1
        switch phase {
        case .loading, .failed, .story:
            return Look(rect: full, opacity: index == current ? 1 : 0, corner: 0, rotation: 0)
        case .scatter:
            if isPeak { return Look(rect: full, opacity: 1, corner: 0, rotation: 0) }
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

    /// A start just past the screen's edges, tilted, a little larger than
    /// the cell -- the photos fly in from all round.
    private func scattered(_ index: Int) -> (CGRect, Double) {
        let anchors: [(x: CGFloat, y: CGFloat, tilt: Double)] = [
            (-0.16, 0.16, -9), (1.16, 0.32, 8), (-0.18, 0.7, 6), (1.18, 0.84, -7),
            (0.22, 1.12, 5), (0.82, -0.1, -6), (0.58, 1.16, 9)
        ]
        let anchor = anchors[index % anchors.count]
        let target = cell(index, settled: false)
        let width = target.width * 1.1
        let height = target.height * 1.1
        let rect = CGRect(x: anchor.x * size.width - width / 2, y: anchor.y * size.height - height / 2,
                          width: width, height: height)
        return (rect, anchor.tilt)
    }
}
