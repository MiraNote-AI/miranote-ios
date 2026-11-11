import XCTest
@testable import MiraNote

/// Limited access: the Recents grid shows the latest shares first, not the
/// newest taken (#167). PhotoKit does not say when a photo was shared, so
/// the first time a photo shows up counts as its share.
final class RecentPhotosOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTheFirstLoadKeepsTheNewestTakenFirst() {
        let order = RecentPhotos.sharedOrder(["b", "a"], sharedAt: nil, now: now)
        XCTAssertEqual(order.ids, ["b", "a"])
        XCTAssertEqual(order.sharedAt, ["b": .distantPast, "a": .distantPast])
    }

    func testAPhotoSharedLaterComesFirstHoweverOldItIs() {
        let first = RecentPhotos.sharedOrder(["b", "a"], sharedAt: nil, now: now)
        // "old" was taken before both, so PhotoKit lists it last.
        let later = RecentPhotos.sharedOrder(["b", "a", "old"], sharedAt: first.sharedAt, now: now)
        XCTAssertEqual(later.ids, ["old", "b", "a"])
    }

    func testTheLatestShareLeadsTheEarlierOnes() {
        var sharedAt = RecentPhotos.sharedOrder(["a"], sharedAt: nil, now: now).sharedAt
        sharedAt = RecentPhotos.sharedOrder(["a", "x"], sharedAt: sharedAt, now: now + 1).sharedAt
        let order = RecentPhotos.sharedOrder(["y", "a", "x"], sharedAt: sharedAt, now: now + 2)
        XCTAssertEqual(order.ids, ["y", "x", "a"], "y was taken last but its share is what counts")
        XCTAssertEqual(order.sharedAt["x"], now + 1, "a photo keeps the time it was first seen")
    }

    func testAPhotoNoLongerSharedIsForgottenAndCountsAsNewWhenSharedAgain() {
        var sharedAt = RecentPhotos.sharedOrder(["a", "b"], sharedAt: nil, now: now).sharedAt
        sharedAt = RecentPhotos.sharedOrder(["b"], sharedAt: sharedAt, now: now + 1).sharedAt
        XCTAssertEqual(sharedAt.keys.sorted(), ["b"])
        XCTAssertEqual(RecentPhotos.sharedOrder(["a", "b"], sharedAt: sharedAt, now: now + 2).ids, ["a", "b"])
        XCTAssertEqual(RecentPhotos.sharedOrder(["b", "a"], sharedAt: sharedAt, now: now + 2).ids, ["a", "b"])
    }

    func testAnEmptyRecordStillCountsAsRecorded() {
        let empty = RecentPhotos.sharedOrder([], sharedAt: nil, now: now)
        XCTAssertEqual(empty.sharedAt, [:])
        let order = RecentPhotos.sharedOrder(["b", "a"], sharedAt: empty.sharedAt, now: now)
        XCTAssertEqual(order.sharedAt, ["b": now, "a": now], "shared after the record began")
        XCTAssertEqual(order.ids, ["b", "a"], "shared together: newest taken first")
    }
}
