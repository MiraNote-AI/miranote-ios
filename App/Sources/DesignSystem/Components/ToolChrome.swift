import SwiftUI

/// The handoff's Ask-Mira composer as each tool page words it (screens
/// 23-36), on the shared `ComposerCapsule` -- action 52 wide, Generate 74.
struct ToolComposer: View {
    let placeholder: String
    /// The typed words; nil when the page takes none and the copy only says
    /// what the action does ("Open Photo Library").
    var text: Binding<String>?
    let action: String
    var actionWidth: CGFloat = 52
    var actionEnabled = true
    let fieldID: String
    let actionID: String
    /// Lets the page follow (and drop) the keyboard.
    var focus: FocusState<Bool>.Binding?
    var onAction: () -> Void

    var body: some View {
        ComposerCapsule(
            action: action, actionID: actionID, canAct: actionEnabled, actionWidth: actionWidth, onAct: onAction
        ) {
            Group {
                if let text {
                    TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(Palette.muted))
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.forest)
                        .submitLabel(.go)
                        .onSubmit { if actionEnabled { onAction() } }
                        .modifier(OptionalFocus(focus: focus))
                } else {
                    Text(placeholder)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.miraComposer)
            .lineLimit(1)
            .accessibilityIdentifier(fieldID)
        }
    }
}

private struct OptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}

/// A 48 pt tall r18 tile, at least 62 wide, of the Photo Editing and Sticker
/// sheets (screens 27, 32-33): paper tile, muted Bold 13 label; selected, a
/// 2 pt ink ring and an
/// ink label.
struct EditTile: View {
    let label: String
    let selected: Bool
    /// #E3DAC8 on Photo Editing; the Sticker style tiles stay #ECE7D8.
    var selectedFill = Palette.tileSelected
    var action: () -> Void

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Sans.font(size: 13, weight: 700))
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                // One line at 13 pt: the tile grows with its word ("AI
                // Editing", "Match page") rather than wrap or shrink it.
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minWidth: 62)
                .frame(height: 48)
                .background(Self.shape.fill(selected ? selectedFill : Palette.cardFill))
                .overlay(
                    Self.shape.strokeBorder(
                        selected ? Palette.ink : Color.black.opacity(0.04),
                        lineWidth: selected ? 2 : 1
                    )
                )
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The handoff's floating 34 pt edit control (screens 27-28, 32-34): an ink
/// circle at 0.92 with a 24 pt paper glyph; active (a held compare), the
/// circle turns paper and the glyph ink.
struct FloatingCircle<Glyph: View>: View {
    var active = false
    @ViewBuilder var glyph: () -> Glyph

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        glyph()
            .foregroundStyle(active ? Palette.ink : Palette.onInk)
            .frame(width: 34, height: 34)
            .background(Circle().fill((active ? Palette.paper : Palette.ink).opacity(0.92)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Circle())
            .padding(5)
            .contentShape(Rectangle())
            .padding(-5)
    }
}

/// The floating cluster's glyphs, drawn from the handoff's own SVGs.
enum FloatingGlyph {
    /// Undo (7d1bb.svg); Redo is the same arrow mirrored (screen 32).
    static func undo(mirrored: Bool = false) -> some View {
        Image("float.undo")
            .renderingMode(.template)
            .resizable()
            .frame(width: 24, height: 24)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }

    /// The split square of Compare (e7370.svg).
    static var compare: some View {
        Image("float.compare")
            .renderingMode(.template)
            .resizable()
            .frame(width: 24, height: 24)
    }

    /// Add to favorite (81516.svg): a star with a small plus badge in the
    /// tile color; filled once the item is a favorite.
    static func favorite(saved: Bool) -> some View {
        ZStack {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
            if !saved {
                Circle()
                    .fill(Palette.cardFill)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    )
                    .offset(x: -5.5, y: 6.5)
            }
        }
        .foregroundStyle(Palette.cardFill)
        .frame(width: 24, height: 24)
    }
}

/// The generating spinner of screen 32: twelve dots on a ring, shading from
/// ink green to pale teal, turning.
struct DotRingSpinner: View {
    var diameter: CGFloat = 122

    private static let colors: [Color] = (0..<12).map { index in
        let t = Double(index) / 11
        // #2F3B33 -> #B9D3D0
        return Color(
            red: (47 + (185 - 47) * t) / 255,
            green: (59 + (211 - 59) * t) / 255,
            blue: (51 + (208 - 51) * t) / 255
        )
    }

    var body: some View {
        TimelineView(.animation) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate * 10) % 12
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(Self.colors[index])
                        .frame(width: 20, height: 20)
                        .offset(y: -(diameter - 20) / 2)
                        .rotationEffect(.degrees(Double(index + step) * 30))
                }
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityElement()
        .accessibilityLabel("Working")
    }
}
