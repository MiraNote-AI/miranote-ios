import SwiftUI

/// Primary call-to-action: ink capsule with a warm-white label.
/// Used for Save, Go, Generate, Save to Photos, Start a memory.
struct PrimaryPill: ButtonStyle {
    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.miraPill)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Palette.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .minimumHitTarget()
    }
}

/// Quiet capsule for navigation and toolbar chips: paper fill, hairline ring.
struct SoftPill: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.miraLabel)
            .foregroundStyle(selected ? Palette.onInk : Palette.ink)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(selected ? Palette.ink : Palette.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: selected ? 0 : Metrics.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .minimumHitTarget()
    }
}

/// The handoff's frosted composer surface: blurred paper at 60 %, a soft
/// white rim and a low shadow.
struct GlassCapsule: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Palette.paper.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.46), lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.1), radius: 13, y: 12)
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
