import SwiftUI

/// Primary call-to-action: ink capsule with a warm-white label.
/// Used for Save, Go, Generate, Save to Photos, Start a memory.
struct PrimaryPill: ButtonStyle {
    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 11
    /// A disabled pill must look it (Generate with an empty prompt).
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.miraPill)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Palette.ink, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .minimumHitTarget()
    }
}

/// Quiet capsule for navigation and toolbar chips: paper fill, hairline ring.
/// A themed screen passes its theme: on Forest's dark green the selected pill
/// takes the gold of Home's Start button and an unselected one is an outline
/// in the theme's light ink. System (the default, the editor's) and Sunlit
/// Pop keep the ink and paper pills.
struct SoftPill: ButtonStyle {
    var selected = false
    var theme = Theme(appearance: .system)

    func makeBody(configuration: Configuration) -> some View {
        let dark = theme.appearance == .forest
        configuration.label
            .font(.miraLabel)
            .foregroundStyle(selected ? theme.onSmallButton(Palette.onInk) : dark ? theme.ink : Palette.ink)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            // Josefin's line box is 1.0 em, so the label alone left the pill
            // ~29 pt; the design's 34 pt floor lets the +5 reach 44.
            .frame(minHeight: 34)
            .background(selected ? theme.smallButton : dark ? .clear : Palette.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(dark ? theme.ink.opacity(0.3) : Palette.hairline,
                                            lineWidth: selected ? 0 : Metrics.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .minimumHitTarget()
    }
}

/// The handoff's frosted composer surface: blurred paper at 60 %, a soft
/// white rim, the 1 pt inner top highlight and a low shadow.
struct GlassCapsule: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Palette.paper.opacity(0.6)))
            .overlay(InnerTopHighlight(shape: Capsule()))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.46), lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.1), radius: 13, y: 12)
    }
}

/// The handoff's glass highlight, CSS `inset 0 1px 1px white@0.48`: the
/// ring just outside the shape, dropped 1 pt and softened, seen only where
/// it falls inside -- a hairline of light along the top inner edge.
struct InnerTopHighlight<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape.inset(by: -1)
            .stroke(Color.white.opacity(0.48), lineWidth: 2)
            .offset(y: 1)
            .blur(radius: 0.5)
            .mask(shape)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Extends the tappable area 5 pt above and below, so the design's 34 pt
    /// pills hit-test at Apple's 44 pt minimum. The padding is added for the
    /// hit shape and taken back for layout, so neither what is drawn nor the
    /// row it sits in changes size.
    func minimumHitTarget() -> some View {
        padding(.vertical, 5)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
    }
}
