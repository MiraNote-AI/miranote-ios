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

    // The folder is shared by stickers and images (issue #30); the kind
    // round-trips through persistence.
    func testImageEntriesKeepTheirKind() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.add(GeneratedSticker(
            prompt: "Beach photo", symbolName: "photo",
            fileName: "beach.png", kind: .image
        ))
        store.add(sticker("cat.png"))

        XCTAssertEqual(store.all().map(\.kind), [.sticker, .image])
    }

    // Favorites persisted before the kind field existed decode as stickers.
    func testPreWideningJSONDecodesAsSticker() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = """
        [{"id":"11111111-2222-3333-4444-555555555555","prompt":"old friend",\
        "symbolName":"sparkles","fileName":"old.png"}]
        """
        try legacy.data(using: .utf8)!.write(to: url)

        let entries = store.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sticker)
        XCTAssertEqual(entries[0].fileName, "old.png")
    }
}
