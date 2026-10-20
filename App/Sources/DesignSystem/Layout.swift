import SwiftUI

/// Shared spacing and radius metrics for Flow 7, tuned against the Figma frames.
/// Named `Metrics` (not `Layout`) to avoid colliding with SwiftUI's `Layout`.
enum Metrics {
    static let screenPadding: CGFloat = 22
    /// Side inset of all chrome -- nav pills, the tool bar, the composers:
    /// one edge.
    static let chromeInset: CGFloat = 16
    /// Side inset of the canvas card (owner, 2026-10-19: as wide as reads
    /// well). The 360 pt page scales up to fill it.
    static let canvasInset: CGFloat = 8
    /// Sheets and panels over the canvas float this far inside the card on
    /// every side -- which puts their edges on the chrome's line.
    static let sheetInCard: CGFloat = chromeInset - canvasInset
    /// The five-tool bar shares the chrome's edge.
    static let toolBarInset: CGFloat = chromeInset
    /// The canvas card: corner, and the tight gaps that frame it vertically
    /// (nav bottom to card top, card bottom to tool bar top).
    static let canvasCorner: CGFloat = 24
    static let navToCanvas: CGFloat = 6
    static let canvasToToolBar: CGFloat = 6
    static let pageCorner: CGFloat = 6
    static let imageCorner: CGFloat = 18
    static let sheetCorner: CGFloat = 26
    static let chipCorner: CGFloat = 13
    static let hairline: CGFloat = 1

    /// The gap under the editor's bottom cluster, inside the safe area: 2
    /// above the home indicator as drawn (36 above the screen edge), 10
    /// above a keyboard, 16 above the edge of a phone without a home
    /// indicator (iPhone SE).
    static func bottomGap(safeAreaBottom inset: CGFloat) -> CGFloat {
        if inset > 100 { return 10 }
        return max(2, 16 - inset)
    }
}
