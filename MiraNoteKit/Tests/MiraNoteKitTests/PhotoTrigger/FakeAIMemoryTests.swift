import XCTest
@testable import MiraNoteKit

final class FakeAIMemoryTests: XCTestCase {
    /// A photo before 04:00 belongs to the day before: so does the weekday
    /// the body names (as the backend does), while the daypart is the cover's.
    func testFakeWeekdayIsTheBelongsToDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        // Sunday 2026-10-18's night, the cover taken at 02:00 on Monday.
        let photos = (1...3).map {
            ComposeMeta.Photo(id: "P\($0)", takenAt: "2026-10-19T0\($0):00:00-05:00", labels: [], faces: 0,
                              favorite: false, edited: false, represents: 1)
        }
        let meta = ComposeMeta(groupKey: "g", date: "2026-10-18", weekday: 7, startTime: "01:00", endTime: "03:00",
                               place: nil, rawCount: 3, coversAll: true, recentQuestionTypes: [], bucket: "event",
                               tz: "America/Chicago", photos: photos)
        let picks = [("L1", 0.4), ("L2", 0.9), ("L3", 0.5)].map {
            Preselected(id: $0.0, reason: .all, score: $0.1, represents: 1)
        }
        let memory = FakeAIMemory.build(meta: meta, photoIds: ["P1": "L1", "P2": "L2", "P3": "L3"], picks: picks,
                                        calendar: calendar, zh: { "[\($0)]" })
        XCTAssertEqual(memory.push.coverPhotoId, "P2")
        XCTAssertTrue(memory.push.body.hasSuffix(" [Sunday] [Night]]"), memory.push.body)
    }
}
