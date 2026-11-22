import SwiftUI

/// One collection card in the Home grid (handoff screen 01): 188 pt tall,
/// r26, the title in Bold 20 at (30, 26) (#D9CDBA, or AA-safe for large
/// text -- see `Style.cycle`), and a 110 x 60 art block
/// with its accent layer 18 above the bottom edge. No note count.
struct HomeCollectionCard: View {
    static let height: CGFloat = 188
    static let corner: CGFloat = 26

    /// The handoff's four card colors, cycled by grid position.
    struct Style {
        let card: Color
        let art: Color
        let accent: Color
        /// The handoff's #D9CDBA where it reads at 3:1 (forest, 8.4:1).
        var title = Color(hex: 0xD9CDBA)
        var border = Color(hex: 0x48433B).opacity(0.12)

        /// Accessibility deviation (decided 2026-10-15, as dev had it): the
        /// handoff's titles read at 1.5-2.5:1 on the grey, olive and tan
        /// cards, under the 3:1 that Bold 20 (large text) needs. Grey and
        /// olive keep the drawn card colors under a paper title (3.5 and
        /// 3.4:1), the tan card takes an ink title (7:1).
        static func cycle(_ index: Int) -> Style {
            let warmAccent = Color(hex: 0x8F7E76).opacity(0.5)
            let coolAccent = Color(hex: 0xEEF1EB).opacity(0.32)
            switch index % 4 {
            case 1: return Style(card: Palette.forest, art: Color(hex: 0xB6C2BA), accent: coolAccent)
            case 2: return Style(card: Color(hex: 0x878476), art: Palette.forest, accent: warmAccent,
                                 title: Palette.onInk)
            case 3: return Style(card: Color(hex: 0xC1A47E), art: Color(hex: 0xC1A47E), accent: coolAccent,
                                 title: Palette.ink)
            default: return Style(card: Color(hex: 0x8F7E76), art: Color(hex: 0xD6BFAA), accent: warmAccent,
                                  title: Palette.onInk)
            }
        }
    }

    let title: String
    let style: Style

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleText
                .foregroundStyle(style.title)
                .frame(width: 118, alignment: .leading)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 18)
                .fill(style.art)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(style.accent))
                .frame(width: 110, height: 60)
        }
        .padding(.top, 27)
        .padding(.leading, 30)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(style.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.corner)
                        .strokeBorder(style.border, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x544738).opacity(0.1), radius: 17, y: 18)
        )
    }

    /// Up to two lines, in Josefin or the theme's face.
    @ViewBuilder private var titleText: some View {
        if let face = theme.cardTitleFace {
            ThemedCardTitle(title: title, face: face, width: 118)
        } else {
            Text(title)
                .font(Sans.font(size: 22, weight: 700))
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
    }
}
