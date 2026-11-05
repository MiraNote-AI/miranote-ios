import XCTest
@testable import MiraNoteKit

/// A GPS fix that is not a place -- an invalid reading, or a camera that
/// wrote 0,0 -- counts as no location: it neither cuts a group nor moves
/// its centre.
final class GeoPointTests: XCTestCase {
    private let home = GeoPoint(lat: 39.9, lon: 116.4)

    func testFixDropsInvalidAndNullIsland() {
        XCTAssertEqual(GeoPoint.fix(lat: 39.9, lon: 116.4, horizontalAccuracy: 10), home)
        XCTAssertNil(GeoPoint.fix(lat: 39.9, lon: 116.4, horizontalAccuracy: -1), "negative accuracy is invalid")
        XCTAssertNil(GeoPoint.fix(lat: 0, lon: 0, horizontalAccuracy: 5))
        XCTAssertNil(GeoPoint.fix(lat: 0.0004, lon: -0.0003, horizontalAccuracy: 5), "near 0,0 too")
        XCTAssertNil(GeoPoint.fix(lat: .nan, lon: 10, horizontalAccuracy: 5))
        XCTAssertNil(GeoPoint.fix(lat: 91, lon: 10, horizontalAccuracy: 5))
        XCTAssertNil(GeoPoint.fix(lat: 10, lon: 181, horizontalAccuracy: 5))
        XCTAssertNotNil(GeoPoint.fix(lat: 0.5, lon: 0, horizontalAccuracy: 5), "the equator is a place")
        XCTAssertNotNil(GeoPoint.fix(lat: 0, lon: 32.6, horizontalAccuracy: 5), "so is longitude 0's neighbour")
    }

    func testNullIslandIsNoLocationOnAssetsAndPhotos() {
        let zero = GeoPoint(lat: 0, lon: 0)
        let asset = LibraryAsset(id: "a", takenAt: nil, location: zero, isFavorite: false, isEdited: false,
                                 isScreenshot: false, isHidden: false, isVideo: false, originalFilename: nil,
                                 burstId: nil)
        XCTAssertNil(asset.location)
        XCTAssertNil(GroupablePhoto(id: "a", takenAt: .now, location: zero, burstId: nil).location)
        XCTAssertEqual(GroupablePhoto(id: "b", takenAt: .now, location: home, burstId: nil).location, home)
    }

    func testNullIslandNeitherCutsNorDragsTheCentre() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14))!
        func photos(spacing minutes: Double) -> [GroupablePhoto] {
            (0..<6).map {
                GroupablePhoto(id: "p\($0)", takenAt: start.addingTimeInterval(Double($0) * minutes * 60),
                               location: $0 == 3 ? GeoPoint(lat: 0, lon: 0) : home, burstId: nil)
            }
        }
        let spread = FragmentGrouper.group(photos(spacing: 25), threshold: 7200, calendar: calendar) { _, _ in nil }
        XCTAssertEqual(spread.fragments.count, 1)
        XCTAssertEqual(spread.cuts, [])
        let tight = FragmentGrouper.group(photos(spacing: 5), threshold: 7200, calendar: calendar) { _, _ in nil }
        let center = try XCTUnwrap(tight.fragments.first?.center)
        XCTAssertLessThan(center.km(to: home), 0.01)
    }
}
