import XCTest
@testable import MiraNoteKit

/// Draft and saved pages (#137): Save is the one way a page becomes saved;
/// leaving any other way keeps it a draft -- except a saved page that
/// leaves unchanged.
@MainActor
final class DraftPageTests: XCTestCase {
    // MARK: The stored flag

    func testAPageSavedBeforeDraftsExistedLoadsAsSaved() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000003","title":"old page",
         "body":"","createdAt":700000000,"memoryDate":700000000,"items":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let memory = try decoder.decode(Memory.self, from: Data(legacy.utf8))
        XCTAssertFalse(memory.isDraft, "pages from before this change count as saved")
    }

    func testADraftStaysADraftThroughARoundTrip() throws {
        let draft = Memory(title: "half a thought", isDraft: true)
        let back = try JSONDecoder().decode(Memory.self, from: JSONEncoder().encode(draft))
        XCTAssertTrue(back.isDraft)
    }

    func testANewMemoryIsSavedUnlessMarked() {
        XCTAssertFalse(Memory(title: "seeded").isDraft, "seeds and old call sites stay saved")
    }
}
