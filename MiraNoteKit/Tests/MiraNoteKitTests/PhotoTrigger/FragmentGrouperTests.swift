import XCTest
@testable import MiraNoteKit

/// The grouping exam (acceptance B1): every row of the example table in
/// the v1 life-fragment grouping rule, with T = 2 hours, plus the threshold's
/// fallbacks and the guards around it.
final class FragmentGrouperTests: XCTestCase {
    private static let zone = TimeZone(identifier: "America/Chicago")!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = FragmentGrouperTests.zone
        return calendar
    }()
    private let twoHours: TimeInterval = 7200
    private let home = GeoPoint(lat: 32.9000, lon: -96.8000)

    /// 2026-10-18 (a Saturday) at `hour`:`minute` in Chicago.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// A point `km` east of `home`.
    private func east(_ km: Double) -> GeoPoint {
        GeoPoint(lat: home.lat, lon: home.lon + km / (111.32 * cos(home.lat * .pi / 180)))
    }

    private func photo(_ id: String, _ date: Date, _ place: GeoPoint?, burst: String? = nil) -> GroupablePhoto {
        GroupablePhoto(id: id, takenAt: date, location: place, burstId: burst)
    }

    private func group(_ photos: [GroupablePhoto], distance: @escaping (String, String) -> Float? = { _, _ in nil })
        -> GroupingResult {
        FragmentGrouper.group(photos, threshold: twoHours, calendar: calendar, distance: distance)
    }

    // MARK: The example table

    /// A two-hour walk over 4 km: mostly under 20 minutes apart, one
    /// 40-minute pause -- under T, and nowhere near 10 km.
    func testAfternoonWalkIsOneGroup() {
        let minutes = [0, 12, 25, 35, 75, 88, 100, 112, 120]
        let photos = minutes.enumerated().map { index, minute in
            photo("w\(index)", at(14).addingTimeInterval(Double(minute) * 60), east(Double(minute) / 30))
        }
        let result = group(photos)
        XCTAssertEqual(result.fragments.map { $0.photos.map(\.id) }, [photos.map(\.id)])
        XCTAssertEqual(result.dropped, [])
    }

    /// 1.5 hours without a photo over lunch: not T, the same park.
    func testAmusementParkLunchGapIsOneGroup() {
        let morning = [0, 10, 20, 30].map { photo("am\($0)", at(10, $0), east(0.2)) }
        let afternoon = [0, 15, 30].map { photo("pm\($0)", at(12, $0), east(0.5)) }   // 10:30 -> 12:00
        let result = group(morning + afternoon)
        XCTAssertEqual(result.fragments.count, 1)
        XCTAssertEqual(result.fragments.first?.uniqueCount, 7)
    }

    /// 23:00 to 01:00: not cut at midnight, and it belongs to the evening's day.
    func testBarbecueAcrossMidnightIsOneGroupOfPreviousDay() {
        let photos = [
            photo("b1", at(23, 0), home), photo("b2", at(23, 25), home), photo("b3", at(23, 50), home),
            photo("b4", at(0, 30, day: 19), home), photo("b5", at(1, 0, day: 19), home)
        ]
        let result = group(photos)
        XCTAssertEqual(result.fragments.count, 1)
        XCTAssertEqual(result.fragments.first?.belongsTo, "2026-10-18")
    }

    /// Dinner, a 40-minute ride of 3 km, karaoke: one group.
    func testDinnerThenKaraoke3kmIsOneGroup() {
        let dinner = [0, 10, 25].map { photo("d\($0)", at(18, $0), home) }
        let karaoke = [0, 15, 40].map { photo("k\($0)", at(19, 5 + $0), east(3)) }    // 18:25 -> 19:05
        let result = group(dinner + karaoke)
        XCTAssertEqual(result.fragments.count, 1)
        XCTAssertEqual(result.fragments.first?.uniqueCount, 6)
    }

    /// One photo per meal, hours apart, in three different places.
    func testThreeMealsAreAllDropped() {
        let photos = [photo("m1", at(8), home), photo("m2", at(12, 30), east(5)), photo("m3", at(19), east(12))]
        let result = group(photos)
        XCTAssertEqual(result.fragments, [])
        XCTAssertEqual(result.dropped.map { $0.map(\.id) }, [["m1"], ["m2"], ["m3"]])
    }

    /// 0:00, 1:00, 3:00, 7:00 at home: cut 1->3 and 3->7; {0,1} and {3}
    /// are one place two hours apart, so they merge; 7:00 is dropped.
    func testLateNightAtHomeMerges013AndDrops7() {
        let photos = [0, 1, 3, 7].map { photo("n\($0)", at($0, 0, day: 19), home) }
        let result = group(photos)
        XCTAssertEqual(result.fragments.map { $0.photos.map(\.id) }, [["n0", "n1", "n3"]])
        XCTAssertEqual(result.dropped.map { $0.map(\.id) }, [["n7"]])
        XCTAssertEqual(result.fragments.first?.belongsTo, "2026-10-18", "before 4 am counts as the day before")
        XCTAssertEqual(result.cuts.map(\.rule), [.timeGap, .timeGap])
    }

    /// A day in town, then an hour's drive to a city 40 km away.
    func testDriveToCity40kmAwayIsTwoGroups() {
        let town = [0, 15, 30, 45].map { photo("t\($0)", at(10, $0), home) }
        let city = [0, 10, 20].map { photo("c\($0)", at(11, 45 + $0), east(40)) }   // 10:45 -> 11:45
        let result = group(town + city)
        XCTAssertEqual(result.fragments.map { $0.photos.map(\.id) }, [town.map(\.id), city.map(\.id)])
        XCTAssertEqual(result.cuts.map(\.rule), [.distance])
    }

    // MARK: Threshold

    func testThresholdFallbackUnder50Gaps() {
        let gaps = Array(repeating: 60.0, count: 30) + Array(repeating: 86_400.0, count: 19)
        let result = PersonalThreshold.compute(gaps: gaps)
        XCTAssertEqual(result, ThresholdResult(value: 7200, fallback: .tooFewGaps))
    }

    func testThresholdFallbackWeakSeparation() {
        // Two piles only three times apart: 10 and 30 minutes.
        let gaps = Array(repeating: 600.0, count: 40) + Array(repeating: 1800.0, count: 40)
        XCTAssertEqual(PersonalThreshold.compute(gaps: gaps), ThresholdResult(value: 7200, fallback: .weakSeparation))
        XCTAssertEqual(PersonalThreshold.compute(gaps: Array(repeating: 600, count: 80)).fallback, .weakSeparation)
    }

    func testThresholdClampedToOneToFourHours() {
        // 1 minute and 30 days: geometric mean ~3.5 h, inside the range.
        let inside = PersonalThreshold.compute(gaps: piles(60, 2_592_000))
        XCTAssertNil(inside.fallback)
        XCTAssertEqual(inside.value, (60 * 2_592_000.0).squareRoot(), accuracy: 1)
        // 5 minutes and 60 days: ~11 h, clamped to 4.
        let high = PersonalThreshold.compute(gaps: piles(300, 5_184_000))
        XCTAssertEqual(high, ThresholdResult(value: 14_400, fallback: .clamped))
        // Half a minute (the floor) and 10 hours: ~17 min, clamped to 1 hour.
        let low = PersonalThreshold.compute(gaps: piles(10, 36_000))
        XCTAssertEqual(low, ThresholdResult(value: 3600, fallback: .clamped))
    }

    /// 60 short gaps and 20 long ones.
    private func piles(_ short: TimeInterval, _ long: TimeInterval) -> [TimeInterval] {
        Array(repeating: short, count: 60) + Array(repeating: long, count: 20)
    }

    // MARK: Guards

    /// Within 120 s of the cluster's first photo and alike (<= 0.30): one
    /// photo. Never chained: the third is compared with the first.
    func testNearDuplicatesCountOnce() {
        let start = at(15)
        let photos = [
            photo("a", start, home), photo("b", start.addingTimeInterval(90), home),
            photo("c", start.addingTimeInterval(200), home),           // 200 s from a: its own cluster
            photo("d", start.addingTimeInterval(260), home),           // alike c, 60 s: dup of c
            photo("e", start.addingTimeInterval(600), home, burst: "B"),
            photo("f", start.addingTimeInterval(601), home, burst: "B"),  // same burst: one
            photo("g", start.addingTimeInterval(900), home)
        ]
        let result = group(photos) { _, _ in 0.2 }
        let fragment = try? XCTUnwrap(result.fragments.first)
        XCTAssertEqual(fragment?.uniqueCount, 4)
        XCTAssertEqual(fragment?.representative, ["b": "a", "d": "c", "f": "e"])
        XCTAssertEqual(fragment?.uniquePhotos.map(\.id), ["a", "c", "e", "g"])

        // Not alike: every photo counts.
        XCTAssertEqual(group(photos) { _, _ in 0.5 }.fragments.first?.uniqueCount, 6)
    }

    /// Thirty hours without a 20-minute pause: split at the longest gaps
    /// until no piece spans more than a day.
    func testLongerThan24HoursIsSplit() {
        var photos: [GroupablePhoto] = []
        var time = at(6)
        for index in 0..<121 {
            photos.append(photo("s\(index)", time, home))
            time.addTimeInterval(index == 40 ? 19 * 60 : 15 * 60)
        }
        let result = group(photos)
        XCTAssertEqual(result.fragments.count, 2)
        XCTAssertEqual(result.fragments.first?.photos.last?.id, "s40")
        for fragment in result.fragments {
            XCTAssertLessThanOrEqual(fragment.end.timeIntervalSince(fragment.start), 86_400)
        }
    }

    /// Photos without GPS group by time alone; a small segment without GPS
    /// cannot be placed and is dropped.
    func testNoGpsSmallSegmentIsDropped() {
        let photos = [photo("x1", at(9), nil), photo("x2", at(9, 10), nil), photo("x3", at(12), nil),
                      photo("x4", at(12, 5), nil), photo("x5", at(12, 10), nil)]
        let result = group(photos)
        XCTAssertEqual(result.fragments.map { $0.photos.map(\.id) }, [["x3", "x4", "x5"]])
        XCTAssertEqual(result.dropped.map { $0.map(\.id) }, [["x1", "x2"]])
    }

    /// Review focus 4: the 4 am rule follows the injected calendar.
    func testBelongsToUsesInjectedCalendar() {
        let photos = [0, 10, 20].map { photo("z\($0)", at(3, $0, day: 19), home) }   // 03:00 Chicago
        XCTAssertEqual(group(photos).fragments.first?.belongsTo, "2026-10-18")
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!                             // 17:00 there
        let elsewhere = FragmentGrouper.group(photos, threshold: twoHours, calendar: tokyo) { _, _ in nil }
        XCTAssertEqual(elsewhere.fragments.first?.belongsTo, "2026-10-19")
    }

    func testGapsAreBetweenSortedNeighbours() {
        let photos = [photo("b", at(10, 5), nil), photo("a", at(10), nil), photo("c", at(10, 30), nil)]
        XCTAssertEqual(PersonalThreshold.gaps(between: photos.map(\.takenAt)), [300, 1500])
    }
}
