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

    func testAPageGoneForGoodTakesItsStarAlong() {
        let shelved = Memory(title: "Shelved"), binned = Memory(title: "Binned"), gone = Memory(title: "Gone")
        for page in [shelved, binned, gone] { XCTAssertNotNil(StarFace.bake(page)) }
        let library = MemoryLibrary(
            collections: [MemoryCollection(title: "Daily Log", memories: [shelved])],
            trash: [TrashedMemory(memory: binned, collectionTitle: "Daily Log")]
        )
        StarFace.forget(allBut: library)
        XCTAssertNotNil(StarFace.cached(shelved.id))
        XCTAssertNotNil(StarFace.cached(binned.id), "a binned page can come back, with its star")
        XCTAssertNil(StarFace.cached(gone.id), "the star of a page gone for good is gone too")
    }
}
