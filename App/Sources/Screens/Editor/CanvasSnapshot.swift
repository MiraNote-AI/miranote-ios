import MiraNoteKit
import SwiftUI
import UIKit

/// The page as the user sees it, for Mira's look_at_page.
///
/// Rendered at the REAL canvas width, not `StaticPageView`'s 360
/// default: the point is to show the model what is on screen.
enum CanvasSnapshot {
    /// Long-edge cap. The canvas scrolls without limit, so a tall page
    /// would otherwise be enormous. Coarse is fine -- precision lives in
    /// the page map; this image only carries impression.
    static let longEdge: CGFloat = 1536

    @MainActor
    static func jpeg(memory: Memory, canvasWidth: CGFloat) -> Data? {
        let renderer = ImageRenderer(
            content: StaticPageView(
                memory: memory, designWidth: canvasWidth, showsSound: false
            )
        )
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return downscaled(image).jpegData(compressionQuality: 0.7)
    }

    @MainActor
    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longEdge else { return image }
        let scale = longEdge / longest
        let target = CGSize(
            width: image.size.width * scale, height: image.size.height * scale
        )
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
