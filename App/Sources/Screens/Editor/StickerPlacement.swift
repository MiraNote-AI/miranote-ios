import MiraNoteKit
import SwiftUI

/// A made sticker's Add (owner, 2026-10-19): it hops from the sheet onto a
/// free spot of the page in view in a quarter second, lands selected, and a
/// toast offers Undo -- no "tap where it should go".
enum StickerSpot {
    /// A placed sticker's side (`CanvasViewModel.addSticker`).
    static let side: CGFloat = 88

    /// The free spot nearest the middle of `visible` (page points) where a
    /// sticker overlaps no element, 8 pt clear; the middle itself when no
    /// spot is free.
    static func find(in visible: CGRect, avoiding items: [CanvasItem]) -> CGPoint {
        let anchor = CGPoint(x: visible.midX, y: visible.midY)
        let taken = items.map {
            CGRect(x: $0.position.x - $0.size.width / 2, y: $0.position.y - $0.size.height / 2,
                   width: $0.size.width, height: $0.size.height).insetBy(dx: -8, dy: -8)
        }
        let half = side / 2 + 8
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for y in stride(from: visible.minY + half, through: visible.maxY - half, by: 8) {
            for x in stride(from: visible.minX + half, through: visible.maxX - half, by: 8) {
                let box = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
                guard !taken.contains(where: { $0.intersects(box) }) else { continue }
                let distance = hypot(x - anchor.x, y - anchor.y)
                if distance < bestDistance {
                    best = CGPoint(x: x, y: y)
                    bestDistance = distance
                }
            }
        }
        return best ?? anchor
    }
}

/// The sticker in flight from the sheet to the page (global points).
struct Flight {
    let image: UIImage
    var x: CGFloat
    var y: CGFloat
    var side: CGFloat
}

/// The sticker the panel's Add just placed: it settles and is announced.
struct Landing: Equatable {
    let itemID: CanvasItem.ID
}

/// The landing sticker arrives 8 % large from its hop and springs to size.
struct Settle: ViewModifier {
    let active: Bool
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && !settled ? 1.08 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { settled = true }
            }
    }
}
