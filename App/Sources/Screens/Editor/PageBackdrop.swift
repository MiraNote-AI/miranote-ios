import MiraNoteKit
import SwiftUI

/// The page's full-bleed backdrop, shared by the editor and the static
/// renderers: the stored background image when the page has one, else
/// the default dawn-to-dusk gradient (mockup, 2026-07-11). A missing
/// file falls back to the gradient -- never a hole.
struct PageBackdrop: View {
    let backgroundFileName: String

    private let imageStore = ImageFileStore()

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [Palette.backdropDawn, Palette.backdropDusk],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(backgroundImage)
    }

    @ViewBuilder private var backgroundImage: some View {
        if !backgroundFileName.isEmpty,
           let data = imageStore.data(forFileName: backgroundFileName),
           let image = UIImage(data: data) {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
    }
}
