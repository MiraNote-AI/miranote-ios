import MiraNoteKit
import SwiftUI

/// The element being moved, as the board measured it: its look, its box on
/// screen (global, unrotated, the drag's translation included) and its tilt.
struct LiftedElement: Equatable {
    let item: CanvasItem
    let frame: CGRect
    let rotation: Double
}

/// Handoff screen 22: the dragged element floats in a scene-level layer,
/// above the tool bar and the composer, with a lift shadow -- never cut at
/// the canvas card's edge. Over the delete zone its selection frame and
/// handles turn red. Purely a picture: the board keeps the gesture.
struct LiftedElementLayer: View {
    let lifted: LiftedElement
    let armed: Bool
    var textFocus: FocusState<CanvasItem.ID?>.Binding

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            CanvasElementView(
                item: lifted.item,
                isSelected: true,
                isEditingText: false,
                isPlaying: false,
                text: .constant(text),
                textFocus: textFocus,
                onTogglePlay: {},
                onEditNote: {}
            )
            .frame(width: lifted.frame.width, height: lifted.frame.height)
            .shadow(color: Color(hex: 0x263521).opacity(0.18), radius: 6, y: 14)
            .overlay { SelectionChrome(size: lifted.frame.size, armed: armed) }
            .rotationEffect(.degrees(lifted.rotation))
            .position(x: lifted.frame.midX - origin.x, y: lifted.frame.midY - origin.y)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var text: String {
        if case .text(let block) = lifted.item.content { return block.text }
        return ""
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
