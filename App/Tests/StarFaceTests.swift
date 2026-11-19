import MiraNoteKit
import XCTest
@testable import MiraNote

/// A page's star (#206): pages from before bake a frame apart, and a page
/// gone for good takes its star along.
@MainActor
final class StarFaceTests: XCTestCase {
    /// The main run loop's turns that went to sleep: each one lets a frame
    /// draw.
    @MainActor private final class Turns {
        var count = 0
    }

    /// A jar of pages from before used to bake them all in one turn of the
    /// main run loop (a `Task.yield()` apart): one stall for the whole jar.
    func testPagesFromBeforeBakeATurnApart() async {
        let turns = Turns()
        let asleep = CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, asleep, true, 0) { _, _ in
            MainActor.assumeIsolated { turns.count += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }

        let pages = (0..<4).map { Memory(title: "Old page \($0)") }
        let bakes = pages.map { page in
            Task { @MainActor in
                let face = await StarFace.bakeInTurn(page)
                return face == nil ? -1 : turns.count
            }
        }
        var bakedIn: [Int] = []
        for bake in bakes { bakedIn.append(await bake.value) }
        XCTAssertFalse(bakedIn.contains(-1), "every page baked")
        XCTAssertEqual(Set(bakedIn).count, pages.count, "each in a turn of its own: \(bakedIn)")
    }

    /// Both folders a star has lived in: the dresses (#206 part B) and
    /// part A's lit stars, which nothing reads any more.
    private func file(_ folder: String, _ page: Memory) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("\(page.id.uuidString).png")
    }

    func testAPageGoneForGoodTakesItsStarAlong() async throws {
        let shelved = Memory(title: "Shelved"), binned = Memory(title: "Binned"), gone = Memory(title: "Gone")
        for page in [shelved, binned, gone] {
            let dress = await StarFace.bake(page)
            XCTAssertNotNil(dress)
        }
        // Part A's lit stars, left from a build before the dresses.
        let lit = try XCTUnwrap(StarFace.cached(shelved.id)?.pngData())
        try FileManager.default.createDirectory(
            at: file("stars", gone).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        for page in [shelved, gone] { try lit.write(to: file("stars", page)) }
        let library = MemoryLibrary(
            collections: [MemoryCollection(title: "Daily Log", memories: [shelved])],
            trash: [TrashedMemory(memory: binned, collectionTitle: "Daily Log")]
        )
        StarFace.forget(allBut: library)
        XCTAssertNotNil(StarFace.cached(shelved.id))
        XCTAssertNotNil(StarFace.cached(binned.id), "a binned page can come back, with its star")
        XCTAssertNil(StarFace.cached(gone.id), "the star of a page gone for good is gone too")
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertTrue(exists(file("star-dress", shelved)) && exists(file("star-dress", binned)))
        XCTAssertFalse(exists(file("star-dress", gone)), "its dress is off the disk")
        XCTAssertTrue(exists(file("stars", shelved)))
        XCTAssertFalse(exists(file("stars", gone)), "and so is its lit star from part A")
    }
}
