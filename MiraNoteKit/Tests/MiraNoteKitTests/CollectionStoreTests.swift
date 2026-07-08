import XCTest
@testable import MiraNoteKit

final class CollectionStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("collections-\(UUID().uuidString).json")
    }

    func testFileStoreSeedsOnFirstLoad() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = FileCollectionStore(url: url).load()

        XCTAssertFalse(loaded.isEmpty, "a fresh install must seed default collections")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the seed must be written to disk")
    }

    func testFileStoreRoundTripsSavedCollections() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let collections = [MemoryCollection(title: "Trips", memories: [Memory(title: "Kyoto")])]
        FileCollectionStore(url: url).save(collections)

        let reloaded = FileCollectionStore(url: url).load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.title, "Trips")
        XCTAssertEqual(reloaded.first?.memories.first?.title, "Kyoto")
    }
}
