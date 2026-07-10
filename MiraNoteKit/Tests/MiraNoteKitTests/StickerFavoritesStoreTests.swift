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
