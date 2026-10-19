import SwiftUI

/// Shared spacing and radius metrics for Flow 7, tuned against the Figma frames.
/// Named `Metrics` (not `Layout`) to avoid colliding with SwiftUI's `Layout`.
enum Metrics {
    static let screenPadding: CGFloat = 22
    /// 2026-10-07 handoff: side inset of the chrome -- nav pills, the Mira
    /// composer, glass sheets (342 wide on the design's 374).
    static let chromeInset: CGFloat = 16
    /// Side inset of the canvas card (334 wide on 374).
    static let canvasInset: CGFloat = 20
    /// Side inset of the five-tool bar (5 x 64 + 4 x 4 on 374).
    static let toolBarInset: CGFloat = 19
    /// The canvas card: corner, and the gaps that frame it vertically
    /// (nav bottom to card top, card bottom to tool bar top).
    static let canvasCorner: CGFloat = 30
    static let navToCanvas: CGFloat = 19
    static let canvasToToolBar: CGFloat = 20
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
