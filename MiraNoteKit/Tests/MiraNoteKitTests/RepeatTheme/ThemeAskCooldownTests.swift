import Foundation
import XCTest
@testable import MiraNoteKit

final class ThemeAskCooldownTests: XCTestCase {
    private var directory: URL!
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_795_262_400)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeAskCooldownTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var store: ThemeAskCooldownStore {
        ThemeAskCooldownStore(file: directory.appendingPathComponent("failed-asks.json"))
    }

    private func ids(_ range: ClosedRange<Int>) -> [String] { range.map { "p\($0)" } }

    func testCoolingByOverlapAgeAndGrowth() throws {
        try store.record(FailedAsk(at: start, photoIds: ids(1...10)))
        XCTAssertTrue(store.isCooling(photoIds: ids(1...10), now: start.addingTimeInterval(6 * day)))
        XCTAssertFalse(store.isCooling(photoIds: ids(1...10), now: start.addingTimeInterval(8 * day)))
        // 1.5x the photos of the failed ask: asked again.
        XCTAssertFalse(store.isCooling(photoIds: ids(1...15), now: start.addingTimeInterval(day)))
        XCTAssertTrue(store.isCooling(photoIds: ids(1...14), now: start.addingTimeInterval(day)))
        // Less than half covered: a different pile.
        XCTAssertFalse(store.isCooling(photoIds: ids(7...16), now: start.addingTimeInterval(day)))
        XCTAssertTrue(store.isCooling(photoIds: ids(6...15), now: start.addingTimeInterval(day)))
    }

    func testRecordDropsOldEntriesAndLoadIsLenient() throws {
        try store.record(FailedAsk(at: start, photoIds: ids(1...3)))
        try store.record(FailedAsk(at: start.addingTimeInterval(8 * day), photoIds: ids(4...6)))
        XCTAssertEqual(store.load().map(\.photoIds), [ids(4...6)])
        try Data("not json".utf8).write(to: directory.appendingPathComponent("failed-asks.json"))
        XCTAssertTrue(store.load().isEmpty)
    }
}
