import MiraNoteKit
import SwiftUI
import UIKit

/// A preset sticker set bundled from the design handoff (screen 35): the
/// images live in the asset catalog under `Stickers/<folder>/<name>`.
struct StickerSet: Identifiable, Equatable {
    let id: String
    let title: String
    let folder: String
    /// In the designer's grid order.
    let names: [String]
    /// The set's tab icon.
    let hero: String

    func imageName(_ name: String) -> String { "Stickers/\(folder)/\(name)" }

    /// The short side, in pixels, a placed preset has at least. Five Food
    /// PNGs are 50 x 22, and Favorites prunes anything under 24 px, so a
    /// favorited one vanished; 72 is the 24 pt cell at 3x.
    static let minPlacedSide: CGFloat = 72

    /// A preset's PNG as the page stores it, scaled up when its short side
    /// is under `minPlacedSide`.
    func placeableData(_ name: String) -> Data? {
        guard let cgImage = UIImage(named: imageName(name))?.cgImage else { return nil }
        return Self.raised(cgImage)
    }

    /// The pixels as PNG, scaled up so the short side is at least
    /// `minPlacedSide`.
    static func raised(_ cgImage: CGImage) -> Data? {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = max(1, minPlacedSide / max(1, min(size.width, size.height)))
        let image = UIImage(cgImage: cgImage)
        guard scale > 1 else { return image.pngData() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let target = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        return UIGraphicsImageRenderer(size: target, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static let food = StickerSet(
        id: "food",
        title: "Food",
        folder: "Food",
        names: [
            "focaccia", "burrito", "hotpot", "martini", "coffee",
            "salad", "chocolate-cake", "donuts", "bibimbap", "sandwich",
            "pizza", "pasta", "sushi", "cream-soup", "iced-tea",
            "fried-chicken", "taco", "ramen", "steak", "quesadilla",
            "dumplings", "boba", "fries", "bakeries", "pudding",
            "burgers", "hotdog", "pancake", "ice-cream", "bao",
        ],
        hero: "focaccia"
    )

    /// The sets the panel offers after Make and Favorites. The handoff's
    /// other tab icons (heart, croissant, cat) have no sets behind them yet.
    static let all: [StickerSet] = [.food]
}

extension StickerFavoritesStore {
    /// The Sticker panel's open-time hygiene. A favorite under the prune's
    /// 24 px short side whose long side is visible -- a 50 x 22 Food preset
    /// placed before presets were raised -- is raised in its own file, as a
    /// preset lands today, and kept; a degenerate thumbnail still goes.
    func prunedRaisingSmall(images: ImageFileStore) -> [GeneratedSticker] {
        pruned(imageSide: { name in
            guard let image = CanvasImageCache.image(fileName: name, filterName: "", store: images) else { return nil }
            let short = min(image.size.width, image.size.height)
            guard short < Self.visibleSide, max(image.size.width, image.size.height) >= Self.visibleSide,
                  let cgImage = image.cgImage, let raised = StickerSet.raised(cgImage),
                  (try? raised.write(to: images.url(forFileName: name), options: .atomic)) != nil else {
                return short
            }
            return StickerSet.minPlacedSide
        }, minSide: Self.visibleSide)
    }

    /// The prune's floor: shorter than this on both sides reads as a blank square.
    private static let visibleSide: CGFloat = 24
}
