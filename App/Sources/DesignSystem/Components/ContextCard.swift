import SwiftUI

/// The rounded panel that rises above the InputModeBar, carrying a scene's
/// contextual controls (choose photos, change filter, create sticker, export).
struct ContextCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.miraCardTitle)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner).fill(Palette.sheetFill))
        .padding(.horizontal, Metrics.screenPadding)
    }
}

/// A pill chip used across the filter / format / tab rows.
struct Chip: View {
    let text: String
    var selected = false
    var fillWhenSelected = true
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? .system(size: 12, weight: .medium) : .miraChip)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
