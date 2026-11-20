import XCTest
@testable import MiraNoteKit

/// A page leaving the bin after 30 days takes its photos and sounds with
/// it (#219); a file another page or a favorite still shows stays.
@MainActor
final class PurgedMediaTests: XCTestCase {
    private var folder: URL!
    private var images: ImageFileStore!
    private var sounds: SoundFileStore!
    private var favorites: StickerFavoritesStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("purge-\(UUID().uuidString)")
        images = ImageFileStore(directory: folder.appendingPathComponent("images"))
        sounds = SoundFileStore(directory: folder.appendingPathComponent("sounds"))
        favorites = StickerFavoritesStore(url: folder.appendingPathComponent("favorites.json"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testPurgedPageFilesGoAndSharedFilesStay() throws {
        let photo = try images.save(Data([1]), id: UUID())
        let sticker = try images.save(Data([2]), id: UUID())
        let backdrop = try images.save(Data([3]), id: UUID())
        let clip = try sounds.save(Data([4]), id: UUID())
        let sharedWithShelf = try images.save(Data([5]), id: UUID())
        let sharedWithBin = try images.save(Data([6]), id: UUID())
        let favorite = try images.save(Data([7]), id: UUID())
        let sharedSound = try sounds.save(Data([8]), id: UUID())
        favorites.add(GeneratedSticker(prompt: "cat", symbolName: "photo", fileName: favorite, kind: .image))

        let old = Date.now.addingTimeInterval(-31 * 24 * 3600)
        let gone = page(images: [photo, sharedWithShelf, sharedWithBin], sticker: sticker,
                        backdrop: backdrop, sounds: [clip, sharedSound])
        let alsoGone = page(images: [favorite], sticker: nil, backdrop: "", sounds: [])
        let shelf = page(images: [sharedWithShelf], sticker: nil, backdrop: "", sounds: [sharedSound])
        let binned = page(images: [], sticker: nil, backdrop: sharedWithBin, sounds: [])
        let store = InMemoryCollectionStore(
            collections: [MemoryCollection(title: "Log", memories: [shelf])],
            trash: [
                TrashedMemory(memory: gone, collectionTitle: "Log", deletedAt: old),
                TrashedMemory(memory: alsoGone, collectionTitle: "Log", deletedAt: old),
                TrashedMemory(memory: binned, collectionTitle: "Log")
            ]
        )

        let viewModel = HomeViewModel(store: store)
        XCTAssertEqual(viewModel.trash.map(\.id), [binned.id])
        XCTAssertTrue(images.exists(fileName: photo), "loading alone deletes nothing: SwiftUI may drop this model")

        viewModel.forgetPurgedMedia(images: images, sounds: sounds, favorites: favorites)

        for name in [photo, sticker, backdrop] {
            XCTAssertFalse(images.exists(fileName: name), "a purged page's own image goes")
        }
        XCTAssertFalse(sounds.exists(fileName: clip), "a purged page's own sound goes")
        XCTAssertTrue(images.exists(fileName: sharedWithShelf), "a shelf page still shows it")
        XCTAssertTrue(images.exists(fileName: sharedWithBin), "a page still in the bin shows it")
        XCTAssertTrue(images.exists(fileName: favorite), "a favorite still shows it")
        XCTAssertTrue(sounds.exists(fileName: sharedSound), "a shelf page still plays it")
    }

    func testNothingPurgedDeletesNothing() throws {
        let photo = try images.save(Data([1]), id: UUID())
        let binned = page(images: [photo], sticker: nil, backdrop: "", sounds: [])
        let store = InMemoryCollectionStore(trash: [TrashedMemory(memory: binned, collectionTitle: "Log")])

        HomeViewModel(store: store).forgetPurgedMedia(images: images, sounds: sounds, favorites: favorites)

        XCTAssertTrue(images.exists(fileName: photo))
    }

    private func page(images: [String], sticker: String?, backdrop: String, sounds: [String]) -> Memory {
        var items = images.map {
            CanvasItem(content: .image(ImageRef(displayName: "photo", fileName: $0)), position: .zero)
        }
        items += sounds.map { CanvasItem(content: .sound(SoundClip(duration: 3, fileName: $0)), position: .zero) }
        if let sticker {
            let made = GeneratedSticker(prompt: "star", symbolName: "sparkles", fileName: sticker)
            items.append(CanvasItem(content: .sticker(made), position: .zero))
        }
        return Memory(title: "Page", items: items, backgroundFileName: backdrop)
    }
}
