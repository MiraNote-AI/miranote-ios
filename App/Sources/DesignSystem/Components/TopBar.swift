import SwiftUI

/// Editor top bar: leading context chip | centered serif title | trailing
/// ink "Save" pill. The title stays optically centered regardless of the
/// leading/trailing widths.
struct TopBar: View {
    var leading: String?
    var leadingSymbol: String?
    let title: String
    var trailing: String? = "Save"
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}

    var body: some View {
        ZStack {
            Text(title)
                .font(.miraScreenTitle)
                .foregroundStyle(Palette.ink)

            HStack {
                if let leading {
                    Button(action: onLeading) {
                        HStack(spacing: 5) {
                            if let leadingSymbol {
                                Image(systemName: leadingSymbol)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(leading)
                        }
                    }
                    .buttonStyle(SoftPill())
                }

                Spacer()

                if let trailing {
                    Button(trailing, action: onTrailing)
                        .buttonStyle(PrimaryPill(horizontalPadding: 18, verticalPadding: 8))
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }
}

/// The Page / Spread / Undo / zoom row beneath the top bar.
struct SubToolbar: View {
    var zoom: String = "86%"

    var body: some View {
        HStack(spacing: 8) {
            chip("Page", emphasized: true)
            chip("Spread")
            chip("Undo")
            Spacer()
            chip(zoom)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 14)
    }

    private func chip(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.miraLabel)
            .foregroundStyle(emphasized ? Palette.ink : Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Palette.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
    }
}
