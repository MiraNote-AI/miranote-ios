import XCTest
@testable import MiraNoteKit

/// The reverse geocoder, failing until told otherwise.
final class FlakyPlaces: PlaceNaming, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var failing = true
    private var lookups = 0

    var fails: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    var count: Int { lock.withLock { lookups } }

    func name(for point: GeoPoint) async throws -> String? {
        let fails = lock.withLock { () -> Bool in
            lookups += 1
            return failing
        }
        if fails { throw Failure() }
        return "Riverside Park"
    }
}

/// A geocoder error is not "no place": the night is not composed without
/// its place (and cached so), it is tried again on a later run.
final class PushSchedulerPlaceTests: PushSchedulerTestCase {
    private let spot = GeoPoint(lat: 32.82, lon: -96.72)

    func testGeocoderErrorLeavesTheGroupForALaterRun() async throws {
        let flaky = FlakyPlaces()
        places = flaky
        library.add("n", start: start.addingTimeInterval(-2 * 86_400 - 6 * 3600), count: 12, location: spot)
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertGreaterThan(flaky.count, 0)
        XCTAssertFalse(client.metas.contains { $0.date == day("n") }, "not composed without its place")
        XCTAssertFalse(activeDays.contains(day("n")))

        flaky.fails = false
        clock.advance(3600)
        await scheduler.appBecameActive()
        let meta = try XCTUnwrap(client.metas.first { $0.date == day("n") })
        XCTAssertEqual(meta.place, "Riverside Park")
        XCTAssertEqual(active.first { $0.belongsTo == day("n") }?.place, "Riverside Park")
    }

    func testNoPlaceThereStillComposes() async throws {
        places = NoPlaces()
        library.add("n", start: start.addingTimeInterval(-2 * 86_400 - 6 * 3600), count: 12, location: spot)
        await makeScheduler().appBecameActive()
        let meta = try XCTUnwrap(client.metas.first { $0.date == day("n") })
        XCTAssertNil(meta.place)
    }
}
