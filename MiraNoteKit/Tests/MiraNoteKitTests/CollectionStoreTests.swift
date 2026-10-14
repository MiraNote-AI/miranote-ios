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

        XCTAssertFalse(loaded.collections.isEmpty, "a fresh install must seed default collections")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the seed must be written to disk")
    }

    func testFileStoreRoundTripsSavedCollections() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let collections = [MemoryCollection(title: "Trips", memories: [Memory(title: "Kyoto")])]
        FileCollectionStore(url: url).save(MemoryLibrary(collections: collections))

        let reloaded = FileCollectionStore(url: url).load()
        XCTAssertEqual(reloaded.collections.count, 1)
        XCTAssertEqual(reloaded.collections.first?.title, "Trips")
        XCTAssertEqual(reloaded.collections.first?.memories.first?.title, "Kyoto")
    }

    func testLegacyBareArrayFileStillLoads() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = [MemoryCollection(title: "Old shelf", memories: [Memory(title: "Kept")])]
        try JSONEncoder().encode(legacy).write(to: url)

        let loaded = FileCollectionStore(url: url).load()
        XCTAssertEqual(loaded.collections.first?.title, "Old shelf")
        XCTAssertTrue(loaded.trash.isEmpty, "pre-bin files decode with an empty bin")
    }

    // A library this build cannot read (written by a later build, or
    // damaged) is moved aside, never overwritten by the seed.
    func testAnUnreadableLibraryIsKeptAsideNotOverwritten() throws {
        let url = tempURL()
        let original = Data(#"{"collections": "a shape this build does not know"}"#.utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = FileCollectionStore(url: url).load()
        XCTAssertFalse(loaded.collections.isEmpty, "the app still opens, on the seed")

        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(stem + ".unreadable-") }
        defer { kept.forEach { try? FileManager.default.removeItem(at: folder.appendingPathComponent($0)) } }
        XCTAssertEqual(kept.count, 1, "the unreadable file is kept beside the new one")
        let aside = try XCTUnwrap(kept.first)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(aside)), original)
    }
}
