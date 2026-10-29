import XCTest
@testable import MiraNoteKit

final class TriggerMemoryTests: XCTestCase {
    /// The file lists the peak first and the rest out of order; the story
    /// still plays by time and ends on the peak.
    private let json = """
    {
      "id": "demo", "mode": "life_fragment", "date": "2025-10-18", "daypart": "afternoon",
      "push": { "title": "Sat \\u00B7 West Lake", "body": "Four shots of the sunset", "coverPhotoId": "05" },
      "story": {
        "firstFrameLabel": "Sat \\u00B7 West Lake",
        "photos": [
          { "id": "05", "file": "05.jpg", "takenAt": "2025-10-18T12:00:00+08:00", "isPeak": true },
          { "id": "02", "file": "02.jpg", "takenAt": "2025-10-18T15:10:00+08:00", "isPeak": false },
          { "id": "01", "file": "01.jpg", "takenAt": "2025-10-18T14:03:00+08:00", "isPeak": false }
        ]
      },
      "ending": { "factLine": "10.18 \\u00B7 West Lake", "question": "What else?", "ctaLabel": "Keep it" }
    }
    """

    func testDecodesTheBackendShape() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.daypart, .afternoon)
        XCTAssertEqual(memory.push.coverPhotoId, "05")
        XCTAssertEqual(memory.ending.factLine, "10.18 \u{00B7} West Lake")
        XCTAssertEqual(memory.story.photos.count, 3)
    }

    func testStoryPlaysByTimeAndEndsOnThePeak() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.storyPhotos.map(\.id), ["01", "02", "05"])
        XCTAssertEqual(memory.peak?.id, "05")
        XCTAssertEqual(memory.coverPhoto?.id, "05")
    }

    func testThePeakLingers() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.storyPhotos.map(TriggerMemory.dwell(for:)), [2, 2, 3])
    }

    func testDaypartBoundaries() {
        XCTAssertEqual([4, 5, 10, 11, 13, 14, 16, 17, 18, 19, 23, 0].map { Daypart(hour: $0) },
                       [.night, .morning, .morning, .noon, .noon, .afternoon, .afternoon,
                        .evening, .evening, .night, .night, .night])
    }

    func testMissingFolderMeansNoMemory() {
        let loader = DemoMemoryLoader(directory: URL(fileURLWithPath: "/nonexistent-demo-memory"))
        XCTAssertNil(loader.load())
        XCTAssertNil(DemoMemoryLoader(directory: nil).load())
    }

    func testLoaderReadsAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(json.utf8).write(to: folder.appendingPathComponent("memory.json"))
        try Data([0xFF]).write(to: folder.appendingPathComponent("01.jpg"))

        let loader = DemoMemoryLoader(directory: folder)
        let memory = try XCTUnwrap(loader.load())
        XCTAssertNotNil(loader.url(for: memory.storyPhotos[0]))
        XCTAssertNil(loader.url(for: memory.storyPhotos[1]), "02.jpg was never written")
    }
}

final class TriggerGridLayoutTests: XCTestCase {
    func testRowsFollowTheHandoff() {
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 2), [2])     // 3 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 3), [3])     // 4 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 4), [4])     // 5 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 5), [3, 2])  // 6 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 6), [3, 3])  // 7 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 7), [4, 3])  // 8 photos
        XCTAssertEqual(TriggerGridLayout.rows(forSmallCount: 0), [])
    }

    func testCellsStayInsideTheCardWithoutOverlapping() {
        for count in 1...8 {
            let layout = TriggerGridLayout(photoCount: count, width: 360)
            let card = CGRect(origin: .zero, size: layout.size)
            let all = [layout.big] + layout.small
            XCTAssertEqual(layout.small.count, count - 1)
            for (i, frame) in all.enumerated() {
                XCTAssertTrue(card.contains(frame), "cell \(i) of \(count) leaves the card")
                for other in all[(i + 1)...] {
                    XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other), "cells overlap at \(count)")
                }
            }
        }
    }

    func testShortScreensCapTheTopCell() {
        XCTAssertEqual(TriggerGridLayout(photoCount: 3, width: 360, maxBigHeight: 120).big.height, 120)
    }
}
