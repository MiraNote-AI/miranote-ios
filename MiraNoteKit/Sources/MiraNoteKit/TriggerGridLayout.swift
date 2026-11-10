import CoreGraphics

/// Where each photo lands on the ending card: the peak photo in one wide cell
/// on top, the rest in time order in one or two rows of small cells under it.
/// Frames are in the card's own space (origin at its top-left corner).
public struct TriggerGridLayout: Equatable, Sendable {
    public static let padding: CGFloat = 12
    public static let gap: CGFloat = 6
    /// The top cell never shrinks below this to fit a short screen.
    public static let minBigHeight: CGFloat = 120
    /// Nor do the small rows give more than this share of their height.
    static let rowGive: CGFloat = 0.2

    public let size: CGSize
    public let big: CGRect
    /// One frame per small photo, in reading order.
    public let small: [CGRect]

    /// Small photos per row, top row first: 3 photos put 2 side by side,
    /// 4-5 photos one row of 3-4, 6-8 photos two rows.
    public static func rows(forSmallCount count: Int) -> [Int] {
        switch count {
        case ..<1: return []
        case 1...4: return [count]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        default:
            // Past the eight a memory is meant to hold: rows of four.
            return stride(from: 0, to: count, by: 4).map { min(4, count - $0) }
        }
    }

    /// - Parameters:
    ///   - photoCount: every photo, the peak included.
    ///   - width: the card's outer width.
    ///   - maxBigHeight: caps the top cell on short screens.
    ///   - maxHeight: the room the card may take; past it the top cell
    ///     shrinks first, then the rows, each down to its floor.
    public init(photoCount: Int, width: CGFloat, maxBigHeight: CGFloat = .infinity,
                maxHeight: CGFloat = .infinity) {
        let pad = Self.padding
        let gap = Self.gap
        let inner = max(0, width - pad * 2)
        let rows = Self.rows(forSmallCount: photoCount - 1)

        var bigHeight = min(inner * 0.66, maxBigHeight)

        // One row of two reads as a pair of near-squares; more cells, or a
        // second row, keep each one shorter so the card stays on screen.
        var rowHeight: CGFloat
        switch (rows.count, rows.first ?? 0) {
        case (1, ...2): rowHeight = inner * 0.48
        case (1, _): rowHeight = inner * 0.36
        default: rowHeight = inner * 0.3
        }

        let rowCount = CGFloat(rows.count)
        let over = pad * 2 + bigHeight + (gap + rowHeight) * rowCount - maxHeight
        if over > 0 {
            let fromBig = min(over, max(0, bigHeight - Self.minBigHeight))
            bigHeight -= fromBig
            if rowCount > 0 { rowHeight -= min((over - fromBig) / rowCount, rowHeight * Self.rowGive) }
        }
        big = CGRect(x: pad, y: pad, width: inner, height: bigHeight)

        var frames: [CGRect] = []
        var top = big.maxY
        for count in rows {
            top += gap
            let cellWidth = (inner - gap * CGFloat(count - 1)) / CGFloat(count)
            for index in 0..<count {
                let left = pad + CGFloat(index) * (cellWidth + gap)
                frames.append(CGRect(x: left, y: top, width: cellWidth, height: rowHeight))
            }
            top += rowHeight
        }
        small = frames
        size = CGSize(width: width, height: top + pad)
    }
}
