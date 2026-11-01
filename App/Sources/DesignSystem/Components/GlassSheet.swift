import SwiftUI

/// The handoff's glass sheet (Choose photos, Photo Editing, Sticker, Export,
/// Background): r30, frosted paper, a 1 pt rim, the inner top highlight and
/// a soft drop shadow, with an optional Josefin Bold title at (21, 17).
///
/// The sheet does not inset itself from the screen edge: chrome sheets sit
/// at `Metrics.chromeInset`, sheets over the canvas card float
/// `Metrics.sheetInCard` inside the card, so the caller pads.
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
    /// 20 on most sheets; 22 (at y 19) on Choose photos, Export, Background
    /// (the handoff's 18 and 20 on the iOS-standard scale, 2026-10-19).
    var titleSize: CGFloat = 20
    /// Paper over the blur: 0.56 on most sheets, 0.50 on the photo grid.
    var fillOpacity: Double = 0.56
    /// White@0.46 on most sheets; Photo Editing and Sticker draw #EEEEE9.
    var border: Color = Color.white.opacity(0.46)
    var elevation: Elevation = .standard
    /// 21 on most sheets; Export closes 11 under its actions.
    var bottomPadding: CGFloat = 21
    @ViewBuilder var content: () -> Content

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 30) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(copy: title)
                            .font(Sans.font(size: titleSize, weight: 700))
                            .foregroundStyle(Palette.ink)
                    }
                    if let subtitle {
                        Text(copy: subtitle)
                            .font(.miraLabel)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            content()
        }
        .padding(.horizontal, 21)
        .padding(.top, titleSize > 20 ? 19 : 17)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var background: some View {
        GlassSurface(
            shape: Self.shape,
            tint: Palette.paper.opacity(fillOpacity),
            rim: border,
            shadowOpacity: elevation == .raised ? 0.16 : 0.10,
            shadowRadius: elevation == .raised ? 18 : 13,
            shadowY: elevation == .raised ? 18 : 12
        )
    }
}

/// The handoff's frosted glass in any shape: blur, a tint over it, the inner
/// top highlight, a 1 pt rim and an ink drop shadow. GlassSheet, the
/// Background tool, the Mira result sheet and the canvas chat panel differ
/// only in these values.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    let tint: Color
    var rim: Color = Color.white.opacity(0.46)
    var highlight = true
    var shadowOpacity: Double = 0.10
    var shadowRadius: CGFloat = 13
    var shadowY: CGFloat = 12

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(tint))
            .overlay { if highlight { InnerTopHighlight(shape: shape) } }
            .overlay(shape.strokeBorder(rim, lineWidth: 1))
            .shadow(color: Palette.ink.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }
}
