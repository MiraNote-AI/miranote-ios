import SwiftUI

/// The handoff's glass sheet (Choose photos, Photo Editing, Sticker, Export,
/// Background): r30, frosted paper, a 1 pt rim, the inner top highlight and
/// a soft drop shadow, with an optional Josefin Bold title at (21, 17).
///
/// The sheet does not inset itself from the screen edge: chrome sheets sit
/// at `Metrics.chromeInset`, the Background panel over the canvas card at
/// `Metrics.canvasInset`, so the caller pads.
struct GlassSheet<Content: View>: View {
    /// The two drop shadows the handoff draws on sheets.
    enum Elevation {
        /// `0 12 26 ink@0.10`: Photo Editing, Sticker.
        case standard
        /// `0 18 36 ink@0.16`: Choose photos grid, Export, Background.
        case raised
    }

    var title: String?
    var subtitle: String?
    /// 18 on most sheets; 20 (at y 19) on Choose photos, Export, Background.
    var titleSize: CGFloat = 18
    /// Paper over the blur: 0.56 on most sheets, 0.50 on the photo grid.
    var fillOpacity: Double = 0.56
    /// White@0.46 on most sheets; Photo Editing and Sticker draw #EEEEE9.
    var border: Color = Color.white.opacity(0.46)
    var elevation: Elevation = .standard
    @ViewBuilder var content: () -> Content

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 30) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .font(Sans.font(size: titleSize, weight: 700))
                            .foregroundStyle(Palette.ink)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.miraComposer)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            content()
        }
        .padding(.horizontal, 21)
        .padding(.top, titleSize > 18 ? 19 : 17)
        .padding(.bottom, 21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var background: some View {
        Self.shape
            .fill(.ultraThinMaterial)
            .overlay(Self.shape.fill(Palette.paper.opacity(fillOpacity)))
            .overlay(InnerTopHighlight(shape: Self.shape))
            .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
            .shadow(
                color: Palette.ink.opacity(elevation == .raised ? 0.16 : 0.10),
                radius: elevation == .raised ? 18 : 13,
                y: elevation == .raised ? 18 : 12
            )
    }
}
