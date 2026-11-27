import XCTest
@testable import MiraNoteKit

/// Round 2 is told when and where each candidate was taken, for occasion
/// small themes only.
final class PushSchedulerThemeFactsTests: PushSchedulerThemeCase {
    private let home = GeoPoint(lat: 41.88, lon: -87.63)

    private func occasion(places: [GeoPoint?], members: [String]) -> ThemeRow {
        var row = small("night", name: "Nights", members: members)
        row.rule = .occasion(keys: places.map { OccasionKey(place: $0, daypart: "evening", weekpart: "weekday") })
        return row
    }

    private func photos(_ ids: [String]) async throws -> [RoundTwoRequest.Photo] {
        _ = await press(makeScheduler(themeEngine: engine()), "night")
        return try XCTUnwrap(rounds.roundTwoRequests.first).photos
    }

    func testOccasionThemeSendsFacts() async throws {
        let ids = try seed("t", days: Array(10...19), location: home)
        try themeLibrary.save([big(members: ids), occasion(places: [home], members: ids)])
        let sent = try await photos(ids)
        XCTAssertEqual(sent.count, 10)
        for photo in sent {
            XCTAssertEqual(photo.daypart, Daypart(hour: 19).rawValue)
            XCTAssertEqual(photo.hour, 19)
            XCTAssertEqual(photo.atPlace, true)
        }
    }

    func testOccasionFactsSayAwayFromEveryPlace() async throws {
        let ids = try seed("t", days: Array(10...19), location: GeoPoint(lat: 42.5, lon: -87.63))
        try themeLibrary.save([big(members: ids), occasion(places: [home], members: ids)])
        let sent = try await photos(ids)
        XCTAssertTrue(sent.allSatisfy { $0.atPlace == false })
    }

    func testRoundTwoFactsOmitPlaceWithoutLocation() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids), occasion(places: [home], members: ids)])
        let sent = try await photos(ids)
        let daypart = Daypart(hour: 19).rawValue
        XCTAssertTrue(sent.allSatisfy { $0.atPlace == nil && $0.hour == 19 && $0.daypart == daypart })
    }

    func testNoPlaceKeysAndNoLocationIsAtPlace() async throws {
        let ids = try seed("t", days: Array(10...19))
        try themeLibrary.save([big(members: ids), occasion(places: [nil], members: ids)])
        let sent = try await photos(ids)
        XCTAssertTrue(sent.allSatisfy { $0.atPlace == true })
    }

    func testBigThemeSendsNoFacts() async throws {
        let ids = try seed("t", days: Array(10...19), location: home)
        try themeLibrary.save([big(members: ids)])
        _ = await press(makeScheduler(themeEngine: engine()), "big")
        let sent = try XCTUnwrap(rounds.roundTwoRequests.first).photos
        XCTAssertTrue(sent.allSatisfy { $0.daypart == nil && $0.hour == nil && $0.atPlace == nil })
    }

    func testContentThemeSendsNoFacts() async throws {
        let ids = try seed("t", days: Array(10...19), location: home)
        try themeLibrary.save([big(members: ids), small("night", name: "Soup", members: ids)])
        let sent = try await photos(ids)
        XCTAssertTrue(sent.allSatisfy { $0.daypart == nil && $0.hour == nil && $0.atPlace == nil })
    }
}
