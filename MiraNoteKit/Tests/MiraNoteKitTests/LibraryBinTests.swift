import XCTest
@testable import MiraNoteKit

/// The 30-day bin, moves between collections, and memory-date compat.
@MainActor
final class LibraryBinTests: XCTestCase {
    func testDeleteMovesToTrashAndRestoreReturnsIt() {
        let seed = [MemoryCollection(title: "Log", memories: [Memory(title: "Keep me")])]
        let viewModel = HomeViewModel(collections: seed)
        let noteID = seed[0].memories[0].id

        viewModel.deleteNote(noteID, from: seed[0].id)
        XCTAssertTrue(viewModel.collections[0].memories.isEmpty)
        XCTAssertEqual(viewModel.trash.count, 1)
        XCTAssertEqual(viewModel.trash[0].collectionTitle, "Log")

        viewModel.restore(noteID)
        XCTAssertTrue(viewModel.trash.isEmpty)
        XCTAssertEqual(viewModel.collections[0].memories[0].title, "Keep me")
    }

    func testTrashPersistsAndExpiresAfterThirtyDays() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HomeViewModel(store: FileCollectionStore(url: url))
        let collection = first.collections[0]
        let noteID = collection.memories[0].id
        first.deleteNote(noteID, from: collection.id)

        let second = HomeViewModel(store: FileCollectionStore(url: url))
        XCTAssertEqual(second.trash.count, 1, "the bin persists")

        let later = Date.now.addingTimeInterval(31 * 24 * 3600)
        let third = HomeViewModel(store: FileCollectionStore(url: url), now: later)
        XCTAssertTrue(third.trash.isEmpty, "the bin purges after 30 days")
    }

    func testMoveRelocatesBetweenCollections() {
        let seed = [
            MemoryCollection(title: "Daily", memories: [Memory(title: "Paris lunch")]),
            MemoryCollection(title: "Travel", memories: [])
        ]
        let viewModel = HomeViewModel(collections: seed)
        let noteID = seed[0].memories[0].id

        viewModel.move(noteID, from: seed[0].id, to: seed[1].id)
        XCTAssertTrue(viewModel.collections[0].memories.isEmpty)
        XCTAssertEqual(viewModel.collections[1].memories[0].title, "Paris lunch")
    }

    func testSetMemoryDateRegroupsAndPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HomeViewModel(store: FileCollectionStore(url: url))
        let collection = first.collections[0]
        let noteID = collection.memories[0].id
        let lastMonth = Date.now.addingTimeInterval(-40 * 24 * 3600)

        first.setMemoryDate(noteID, in: collection.id, to: lastMonth)
        XCTAssertEqual(first.note(noteID, in: collection.id)?.memoryDate, lastMonth)

        let second = HomeViewModel(store: FileCollectionStore(url: url))
        XCTAssertEqual(second.note(noteID, in: collection.id)?.memoryDate, lastMonth, "the about-date persists")
    }

    func testLibrarySearchFindsAcrossTitleBodyAndSoundNotes() {
        let library = MemoryLibrary(collections: [
            MemoryCollection(title: "Daily", memories: [
                Memory(title: "Lunch by the river", body: "tiny noodle shop by the bridge"),
                Memory(title: "Quiet morning", items: [
                    CanvasItem(content: .sound(SoundClip(duration: 5, note: "rain on the window")), position: .zero)
                ])
            ])
        ])

        let noodle = LibrarySearch.find("noodle shop", in: library)
        XCTAssertEqual(noodle.first?.memory.title, "Lunch by the river")

        let rain = LibrarySearch.find("rain", in: library)
        XCTAssertEqual(rain.first?.memory.title, "Quiet morning", "sound notes are searchable")

        XCTAssertTrue(LibrarySearch.find("zeppelin", in: library).isEmpty)
        XCTAssertTrue(LibrarySearch.find("  ", in: library).isEmpty)
    }

    func testLibrarySearchRanksTitleMatchesFirst() {
        let library = MemoryLibrary(collections: [
            MemoryCollection(title: "Daily", memories: [
                Memory(title: "Paris lunch", body: "a bistro"),
                Memory(title: "Random day", body: "we talked about paris a lot")
            ])
        ])
        let hits = LibrarySearch.find("paris", in: library)
        XCTAssertEqual(hits.first?.memory.title, "Paris lunch", "title matches outrank body matches")
        XCTAssertEqual(hits.count, 2)
    }

    func testLegacyMemoryDateDefaultsToCreatedAt() throws {
        let created = Date(timeIntervalSince1970: 700_000_000)
        let legacy = Data("""
        {"id":"\(UUID().uuidString)","title":"old","createdAt":700000000}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Memory.self, from: legacy)
        XCTAssertEqual(decoded.memoryDate, created)
    }
}
