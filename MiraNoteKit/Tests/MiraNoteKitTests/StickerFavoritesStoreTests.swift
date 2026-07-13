import XCTest
@testable import MiraNoteKit

final class StickerFavoritesStoreTests: XCTestCase {
    private func makeStore() -> (StickerFavoritesStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("favorites-test-\(UUID().uuidString).json")
        return (StickerFavoritesStore(url: url), url)
    }

    private func sticker(_ file: String) -> GeneratedSticker {
        GeneratedSticker(prompt: file, symbolName: "sparkles", fileName: file)
    }

    func testRemoveDropsOnlyThatFavorite() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let keep = sticker("keep.png")
        let drop = sticker("drop.png")
        store.add(keep)
        store.add(drop)

        store.remove(id: drop.id)

        XCTAssertEqual(store.all().map(\.fileName), ["keep.png"])
    }

    func testDecodingPreKindJSONDefaultsToSticker() throws {
        // Favorites persisted before `kind` existed must load as stickers.
        let json = #"[{"id":"00000000-0000-0000-0000-000000000001","prompt":"p","symbolName":"sparkles","fileName":"a.png"}]"#
        let decoded = try JSONDecoder().decode([GeneratedSticker].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.kind, .sticker)
    }

    func testImageKindRoundTripsThroughTheStore() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.add(GeneratedSticker(
            prompt: "Library photo", symbolName: "photo", fileName: "p.png", kind: .image
        ))

        XCTAssertEqual(store.all().first?.kind, .image)
    }

    func testPrunedDropsMissingAndDegenerateThumbnails() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.add(sticker("good.png"))
        store.add(sticker("tiny-mock-debris.png"))
        store.add(sticker("file-is-gone.png"))

        let sides: [String: CGFloat] = ["good.png": 512, "tiny-mock-debris.png": 8]
        let kept = store.pruned(imageSide: { sides[$0] })

        XCTAssertEqual(kept.map(\.fileName), ["good.png"],
                       "missing files and 8x8 debris both leave the row")
        XCTAssertEqual(store.all().map(\.fileName), ["good.png"],
                       "the prune persists -- next launch starts clean")
    }

    func testPrunedKeepsAHealthyRowUntouched() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.add(sticker("a.png"))
        store.add(sticker("b.png"))

        let kept = store.pruned(imageSide: { _ in 256 })

        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(store.all().count, 2)
    }
}
