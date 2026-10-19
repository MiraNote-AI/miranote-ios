import MiraNoteKit
import SwiftUI

/// The element being moved, as the board measured it: its look, its box on
/// screen (global, unrotated -- the element's own size -- the drag's
/// translation included), its tilt and the finger (global).
struct LiftedElement: Equatable {
    let item: CanvasItem
    let frame: CGRect
    let rotation: Double
    let finger: CGPoint

    /// `measured` is the element's box as read on screen, tilt included --
    /// for a tilted element its larger bounding box. The copy is drawn at
    /// the element's own `size` around that box's centre, then tilted.
    init(item: CanvasItem, measured: CGRect, size: CGSize, rotation: Double, finger: CGPoint) {
        self.item = item
        frame = CGRect(x: measured.midX - size.width / 2, y: measured.midY - size.height / 2,
                       width: size.width, height: size.height)
        self.rotation = rotation
        self.finger = finger
    }
}

/// Where the dragged element is, updated every frame of a move. A reference
/// that only `LiftedLayerHost` reads: a frame re-renders that layer, not
/// the canvas scene (owner, TestFlight 1.0(5): photo drags were not smooth
/// while the whole scene re-rendered per frame).
@MainActor
@Observable
final class LiftTracker {
    var lifted: LiftedElement?
}

/// The scene's slot for the lifted copy: reads the tracker in its own body.
struct LiftedLayerHost: View {
    let tracker: LiftTracker
    let armed: Bool
    let zoneTop: CGFloat?
    var textFocus: FocusState<CanvasItem.ID?>.Binding

    var body: some View {
        if let lifted = tracker.lifted {
            LiftedElementLayer(lifted: lifted, armed: armed, zoneTop: zoneTop, textFocus: textFocus)
        }
    }
}

/// Handoff screen 22: the dragged element floats in a scene-level layer,
/// above the tool bar and the composer -- never cut at the canvas card's
/// edge. An ordinary move shows the element itself, at its size, under the
/// finger; only armed over the delete zone does it shrink into the
/// design's compact card with a shadow and a red frame (owner decision).
/// Purely a picture: the board keeps the gesture.
struct LiftedElementLayer: View {
    let lifted: LiftedElement
    let armed: Bool
    /// The delete zone's top edge (global), once measured: the card rides on
    /// it, never over the zone's two lines.
    let zoneTop: CGFloat?
    var textFocus: FocusState<CanvasItem.ID?>.Binding

    var body: some View {
        if armed {
            CompactLift(lifted: lifted, zoneTop: zoneTop, textFocus: textFocus)
        } else {
            GeometryReader { geo in
                let bounds = geo.frame(in: .global)
                let full = lifted.frame
                LiftedElementView(item: lifted.item, size: full.size, textFocus: textFocus)
                    .overlay { SelectionChrome(size: full.size, armed: false) }
                    .rotationEffect(.degrees(lifted.rotation))
                    .position(x: full.midX - bounds.minX, y: full.midY - bounds.minY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The element as the page draws it, selected, at `size`.
private struct LiftedElementView: View {
    let item: CanvasItem
    let size: CGSize
    var textFocus: FocusState<CanvasItem.ID?>.Binding

    var body: some View {
        CanvasElementView(
            item: item,
            isSelected: true,
            isEditingText: false,
            isPlaying: false,
            text: .constant(text),
            textFocus: textFocus,
            onTogglePlay: {},
            onEditNote: {}
        )
        .frame(width: size.width, height: size.height)
    }

    private var text: String {
        if case .text(let block) = item.content { return block.text }
        return ""
    }
}

/// Armed over the delete zone: the element shrinks from its page size into
/// the design's compact card (163.7 x 82.3) under the finger, red-framed.
private struct CompactLift: View {
    let lifted: LiftedElement
    let zoneTop: CGFloat?
    var textFocus: FocusState<CanvasItem.ID?>.Binding

    /// The handoff's lifted card: 163.7 x 82.3.
    private static let card = CGSize(width: 163.7, height: 82.3)

    @State private var shrunk = false

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.frame(in: .global)
            let size = compactSize
            let full = lifted.frame
            let center = cardCenter(size: size, in: bounds)
            content(size: size)
                .shadow(color: Color(hex: 0x263521).opacity(0.18), radius: 6, y: 14)
                .overlay { SelectionChrome(size: size, armed: true) }
                .rotationEffect(.degrees(lifted.rotation))
                // The drag starts from the element at page size and shrinks
                // into the card under the finger.
                .scaleEffect(shrunk ? 1 : full.width / size.width)
                .offset(shrunk ? .zero : CGSize(width: full.midX - center.x, height: full.midY - center.y))
                .animation(.spring(duration: 0.25), value: shrunk)
                .position(x: center.x - bounds.minX, y: center.y - bounds.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { shrunk = true }
    }

    /// Words with no fill of their own are set as the handoff's dark card;
    /// anything else is the element itself, scaled down to fit the card.
    private var textCard: TextBlock? {
        if case .text(let block) = lifted.item.content, block.backgroundColorName.isEmpty { return block }
        return nil
    }

    private var compactSize: CGSize {
        if textCard != nil { return Self.card }
        let size = lifted.frame.size
        let scale = min(1, Self.card.width / size.width, Self.card.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Shrunk toward the finger, kept 16 inside the screen's sides and its
    /// bottom on the zone's top edge.
    private func cardCenter(size: CGSize, in bounds: CGRect) -> CGPoint {
        let full = lifted.frame
        let finger = lifted.finger
        let scale = size.width / full.width
        var center = CGPoint(
            x: finger.x + (full.midX - finger.x) * scale,
            y: finger.y + (full.midY - finger.y) * scale
        )
        let inset = size.width / 2 + 16
        center.x = min(max(center.x, bounds.minX + inset), bounds.maxX - inset)
        if let zoneTop { center.y = min(center.y, zoneTop + 2 - size.height / 2) }
        return center
    }

    @ViewBuilder private func content(size: CGSize) -> some View {
        if let block = textCard {
            Text(block.text)
                .font(Sans.font(size: 17, weight: 700))
                .foregroundStyle(Palette.warmWhite)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(width: 155)
                .frame(width: size.width, height: size.height)
                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.ink.opacity(0.77)))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.warmWhite.opacity(0.65), lineWidth: 1))
        } else {
            LiftedElementView(item: lifted.item, size: lifted.frame.size, textFocus: textFocus)
                .scaleEffect(size.width / lifted.frame.width)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// The lifted element's selection: the board's dashed ink frame and round
/// handles while it moves; over the delete zone the handoff's red -- a
/// dashed #D86C5D frame 7 pt out, r16, and 12x11 r5 handles on its corners.
struct SelectionChrome: View {
    let size: CGSize
    let armed: Bool

    var body: some View {
        let outset: CGFloat = armed ? 7 : 0
        let frame = CGSize(width: size.width + outset * 2, height: size.height + outset * 2)
        ZStack {
            RoundedRectangle(cornerRadius: armed ? 16 : 10)
                .strokeBorder(
                    armed ? DeleteDropZone.red : Palette.ink.opacity(0.55),
                    style: StrokeStyle(lineWidth: armed ? 1 : 1.2, dash: armed ? [4, 3] : [5, 4])
                )
                .frame(width: frame.width, height: frame.height)
            ForEach(HandleCorner.allCases, id: \.self) { corner in
                handle
                    .offset(x: corner.sign.x * frame.width / 2, y: corner.sign.y * frame.height / 2)
            }
        }
    }

    @ViewBuilder private var handle: some View {
        if armed {
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.warmWhite)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DeleteDropZone.red, lineWidth: 1))
                .frame(width: 12.4, height: 11.1)
        } else {
            Circle()
                .fill(Palette.onInk)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.4))
                .frame(width: 14, height: 14)
        }
    }
}
