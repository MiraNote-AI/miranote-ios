import MiraNoteKit
import SwiftUI

/// Round 3 of sticker Add (`UIVariant.placeFlow`): where a made sticker
/// lands when Add picks the spot, and how it arrives.
enum StickerSpot {
    /// A placed sticker's side (`CanvasViewModel.addSticker`).
    static let side: CGFloat = 88

    /// The free spot nearest `anchor` inside `visible` (page points) where a
    /// sticker overlaps no element, 8 pt clear; the anchor itself when no
    /// spot is free.
    static func find(in visible: CGRect, near anchor: CGPoint, avoiding items: [CanvasItem]) -> CGPoint {
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

    /// The anchor a flow aims for: beside the newest element for
    /// stay-and-stack, else the middle of what is in view.
    static func anchor(in visible: CGRect, items: [CanvasItem]) -> CGPoint {
        if UIVariant.placeFlow == .stayAndStack, let newest = items.max(by: { $0.zIndex < $1.zIndex }) {
            return newest.position
        }
        return CGPoint(x: visible.midX, y: visible.midY)
    }
}

/// Flow 2's sticker waiting on the page, in page points.
struct GhostPlacement {
    let image: UIImage
    let at: CGPoint
    let place: (CGPoint) -> Void
}

/// Flow 3: the sticker in flight from the sheet to the page (global).
struct Flight {
    let image: UIImage
    var x: CGFloat
    var y: CGFloat
    var side: CGFloat
}

/// Flow 5: the sticker just stacked onto the page from the open panel.
struct Stacked: Equatable {
    let at: CGPoint
    let changeCount: Int
}

/// Flow 5's ring: blooms out from the landed sticker twice and fades.
struct LandingRing: View {
    let side: CGFloat
    @State private var bloom = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .strokeBorder(Palette.onInk, lineWidth: 3)
            .frame(width: side + 16, height: side + 16)
            .scaleEffect(bloom ? 1.25 : 0.9)
            .opacity(bloom ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9 * UIVariant.slowmo).repeatCount(2, autoreverses: false)) {
                    bloom = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// A sticker the canvas has just placed for the user: how it arrives.
struct Landing: Equatable {
    let itemID: CanvasItem.ID
    /// Drops in: from 1.35x and clear to its size, on a spring.
    var dropIn = true
    /// "Added - drag to move" with Undo, at the card's foot.
    var toast = false
}

/// The drop-in of a landing sticker, run once as it appears.
struct DropIn: ViewModifier {
    let active: Bool
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && !landed ? 1.35 : 1)
            .opacity(active && !landed ? 0 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.spring(response: 0.38 * UIVariant.slowmo, dampingFraction: 0.58)) { landed = true }
            }
    }
}

/// Flow 2's ghost: the sticker, half there and breathing, with a chip that
/// says what to do. Dragging makes it solid; it lands where let go, a tap
/// drops it where it is.
struct PlacementGhost: View {
    let image: UIImage
    /// Screen points per page point (the card may scale the page).
    let scale: CGFloat
    let onPlace: (CGSize) -> Void
    @State private var breathing = false
    @GestureState private var drag: CGSize?

    var body: some View {
        let dragging = drag != nil
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: StickerSpot.side, height: StickerSpot.side)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Palette.onInk, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .opacity(dragging ? 0 : 0.9)
                )
                .opacity(dragging ? 1 : 0.6)
                .scaleEffect(dragging ? 1.06 : (breathing ? 1.04 : 0.96))
                .shadow(color: Palette.ink.opacity(dragging ? 0.28 : 0.1), radius: 12, y: 8)
            // Below the sticker: the page's words sit above most free spots.
            Text(dragging ? "Let go to place it" : "Drag to place - tap to drop here")
                .font(.miraChip)
                .foregroundStyle(Palette.onInk)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Palette.ink.opacity(0.88)))
                .fixedSize()
        }
        // The chip rides below: the sticker's centre stays the spot.
        .offset(y: 19)
        .offset(drag.map { CGSize(width: $0.width / scale, height: $0.height / scale) } ?? .zero)
        .contentShape(Rectangle())
        .gesture(
            // Global, as the canvas's own moves: the ghost's offset must
            // not move the space its drag is read in.
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    onPlace(CGSize(width: value.translation.width / scale, height: value.translation.height / scale))
                }
        )
        .onTapGesture { onPlace(.zero) }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Sticker to place")
        .accessibilityHint("Drag to place it, or tap to drop it here.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("canvas.ghost")
    }
}
