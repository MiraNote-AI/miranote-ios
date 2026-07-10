import SwiftUI

/// The journal page laid on paper: serif title, caption, image area, and a
/// few text lines. An optional overlay sits inside the image area (entered
/// text, a placed sticker, a filter tint).
struct MemoryPage<Overlay: View>: View {
    let title: String
    let caption: String
    var imageTint: Color = Palette.tan
    var imageHeight: CGFloat = 188
    var textLines: Int = 3
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.miraPageTitle)
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)

            GradientPlaceholder(tint: imageTint)
                .frame(height: imageHeight)
                .overlay { overlay() }
                .padding(.top, 4)

            TextLines(count: textLines)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.screenPadding)
    }
}

extension MemoryPage where Overlay == EmptyView {
    init(
        title: String,
        caption: String,
        imageTint: Color = Palette.tan,
        imageHeight: CGFloat = 188,
        textLines: Int = 3
    ) {
        self.init(
            title: title,
            caption: caption,
            imageTint: imageTint,
            imageHeight: imageHeight,
            textLines: textLines,
            overlay: { EmptyView() }
        )
    }
}

/// The stack of light bars standing in for body copy on the page.
struct TextLines: View {
    var count: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(Palette.hairline)
                    .frame(height: 7)
                    .frame(maxWidth: idx == count - 1 ? 170 : .infinity, alignment: .leading)
            }
        }
    }
}
