import SwiftUI

/// Shared spacing and radius metrics for Flow 7, tuned against the Figma frames.
/// Named `Metrics` (not `Layout`) to avoid colliding with SwiftUI's `Layout`.
enum Metrics {
    static let screenPadding: CGFloat = 22
    static let pageCorner: CGFloat = 6
    static let imageCorner: CGFloat = 18
    static let cardCorner: CGFloat = 22
    static let sheetCorner: CGFloat = 26
    static let chipCorner: CGFloat = 13
    static let hairline: CGFloat = 1
}
