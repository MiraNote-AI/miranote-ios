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

    /// A Food preset favorited before presets were raised holds its 50 x 22
    /// file: opening the panel keeps it (raised, as a preset now lands),
    /// and still drops a degenerate mock-era thumbnail.
    func testAFavoritePlacedBeforeTheSizeFixIsKeptAndRaised() throws {
        let images = ImageFileStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("favorite-images-\(UUID().uuidString)", isDirectory: true))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thin = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 22), format: format).pngData { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 22))
        }
        let thinFile = try images.save(thin, id: UUID())
        let tinyFile = try images.save(MockImageStudioService.tinyPNG, id: UUID())
        let store = StickerFavoritesStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("old-favorites-\(UUID().uuidString).json"))
        store.add(GeneratedSticker(prompt: "fries", symbolName: "sparkles", fileName: thinFile))
        store.add(GeneratedSticker(prompt: "mock", symbolName: "sparkles", fileName: tinyFile))

        let kept = store.prunedRaisingSmall(images: images)
        XCTAssertEqual(kept.map(\.fileName), [thinFile], "the old preset stays, the 8 px thumbnail goes")
        XCTAssertEqual(store.all().map(\.fileName), [thinFile], "and stays the next time too")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(shortSide(images.data(forFileName: thinFile))),
                                    StickerSet.minPlacedSide, "its file is raised like a preset placed today")
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
