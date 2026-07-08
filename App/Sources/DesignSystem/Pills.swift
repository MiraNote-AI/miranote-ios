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
    }
}
