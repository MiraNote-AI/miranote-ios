import SwiftUI

/// The rounded panel that rises above the InputModeBar, carrying a scene's
/// contextual controls (choose photos, change filter, create sticker, export).
/// Drawn as the handoff's glass sheet at the chrome inset.
struct ContextCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSheet(title: title, subtitle: subtitle, content: content)
            .padding(.horizontal, Metrics.chromeInset)
    }
}

/// A pill chip used across the filter / format / tab rows.
struct Chip: View {
    let text: String
    var selected = false
    var fillWhenSelected = true
    var compact = false
    /// Optional leading SF Symbol (e.g. sparkles on the AI action).
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 10 : 12, weight: .medium))
            }
            Text(text)
                .font(compact ? Sans.font(size: 14, weight: 500) : .miraChip)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(selected && fillWhenSelected ? Palette.onInk : Palette.ink)
        .padding(.horizontal, compact ? 12 : 15)
        .padding(.vertical, compact ? 8 : 9)
        .background(background)
    }

    @ViewBuilder private var background: some View {
        if selected && fillWhenSelected {
            Capsule().fill(Palette.ink)
        } else {
            Capsule()
                .fill(Palette.paper)
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Palette.ink : Palette.hairline,
                        lineWidth: selected ? 1.5 : Metrics.hairline
                    )
                )
        }
    }
}
