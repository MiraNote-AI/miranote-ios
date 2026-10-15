import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// Food presets land on the page at a size Favorites keeps: five handoff
/// PNGs are 50 x 22, and a favorite under 24 px is pruned the next time
/// the panel opens.
final class StickerPresetTests: XCTestCase {
    private func shortSide(_ data: Data?) -> CGFloat? {
        guard let data, let image = UIImage(data: data) else { return nil }
        return min(image.size.width * image.scale, image.size.height * image.scale)
    }

    func testEveryPlacedPresetSurvivesTheFavoritesPrune() throws {
        let set = StickerSet.food
        var sides: [String: CGFloat] = [:]
        for name in set.names {
            sides[name] = try XCTUnwrap(shortSide(set.placeableData(name)), name)
        }
        let store = StickerFavoritesStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("preset-favorites-\(UUID().uuidString).json"))
        for name in set.names {
            store.add(GeneratedSticker(prompt: name, symbolName: "sparkles", fileName: name))
        }
        let kept = store.pruned(imageSide: { sides[$0] })
        XCTAssertEqual(Set(kept.map(\.fileName)), Set(set.names), "no favorited preset is pruned")
        for (name, side) in sides {
            XCTAssertGreaterThanOrEqual(side, StickerSet.minPlacedSide, name)
        }
    }

    func testALargePresetIsStoredAsItCame() throws {
        let set = StickerSet.food
        let raw = try XCTUnwrap(UIImage(named: set.imageName(set.hero))?.cgImage)
        let placed = try XCTUnwrap(UIImage(data: try XCTUnwrap(set.placeableData(set.hero)))?.cgImage)
        if CGFloat(min(raw.width, raw.height)) >= StickerSet.minPlacedSide {
            XCTAssertEqual(placed.width, raw.width)
            XCTAssertEqual(placed.height, raw.height)
        }
    }
}
