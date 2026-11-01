import XCTest
@testable import MiraNoteKit

final class TriggerMemoryTests: XCTestCase {
    /// v0's shape (no detail, question id, bucket or facts): the peak is
    /// listed first and the rest out of order.
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

    /// V1 (handoff 7.7): the peak opens the story, the rest follow by time.
    func testStoryPhotosPutPeakFirstThenTimeOrder() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.storyPhotos.map(\.id), ["05", "01", "02"])
        XCTAssertEqual(memory.peak?.id, "05")
        XCTAssertEqual(memory.coverPhoto?.id, "05")
    }

    func testDwellIsThreeSecondsForPeakTwoOtherwise() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.storyPhotos.map(TriggerMemory.dwell(for:)), [3, 2, 2])
    }

    func testOldJSONDecodesWithDefaults() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        XCTAssertEqual(memory.ending.detail, "")
        XCTAssertEqual(memory.ending.questionId, "")
        XCTAssertEqual(memory.bucket, "")
        XCTAssertEqual(memory.facts, [:])
        XCTAssertNil(memory.generation)
    }

    func testDecodesHandoffExample() throws {
        let data = try Data(contentsOf: Fixtures.url("compose_ok.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memoryData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["memory"]))
        let memory = try TriggerMemory.decode(memoryData)
        XCTAssertEqual(memory.daypart, .evening)
        XCTAssertEqual(memory.ending.questionId, "A1")
        XCTAssertFalse(memory.ending.detail.isEmpty)
        XCTAssertFalse(memory.bucket.isEmpty)
        XCTAssertEqual(memory.storyPhotos.map(\.id), ["P9", "P2"])
        XCTAssertNotNil(memory.facts["P9"])
        XCTAssertEqual(memory.generation?.latencyMs, 41000)
        XCTAssertNil(memory.story.photos[0].file)
    }

    func testPhotoFileIsOptional() throws {
        let photo = try TriggerMemory.decoder.decode(
            TriggerMemory.Photo.self,
            from: Data(#"{"id": "P1", "takenAt": "2026-10-18T14:03:00-05:00", "isPeak": false}"#.utf8)
        )
        XCTAssertNil(photo.file)
    }

    func testRoundTripsThroughTheEncoder() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8))
        let again = try TriggerMemory.decoder.decode(TriggerMemory.self, from: TriggerMemory.encoder.encode(memory))
        XCTAssertEqual(again, memory)
    }

    func testMissingPeakIsReplacedByEarliestRemaining() throws {
        let memory = try TriggerMemory.decode(Data(json.utf8)).replacingMissing(present: ["01", "02", "03"])
        XCTAssertNil(memory, "only two of the listed photos remain")
        let four = Self.memory(ids: ["05", "01", "02", "03"], peak: "05")
        let replaced = try XCTUnwrap(four.replacingMissing(present: ["01", "02", "03"]))
        XCTAssertEqual(replaced.peak?.id, "01")
        XCTAssertEqual(replaced.storyPhotos.map(\.id), ["01", "02", "03"])
        XCTAssertEqual(replaced.storyPhotos.map(\.isPeak), [true, false, false])
    }

    func testFewerThanThreeRemainingIsNil() {
        let four = Self.memory(ids: ["05", "01", "02", "03"], peak: "05")
        XCTAssertNil(four.replacingMissing(present: ["01", "05"]))
        XCTAssertNotNil(four.replacingMissing(present: ["01", "05", "02"]))
    }

    /// An edited photo keeps its localIdentifier, so it is present: only a
    /// deletion takes a photo out (review focus 2).
    func testEditedPhotoStillPresent() throws {
        let four = Self.memory(ids: ["05", "01", "02", "03"], peak: "05")
        let all = try XCTUnwrap(four.replacingMissing(present: ["05", "01", "02", "03"]))
        XCTAssertEqual(all, four)
    }

    func testNoFlaggedPeakFallsBackToEarliest() {
        let memory = Self.memory(ids: ["01", "02", "03"], peak: nil)
        XCTAssertEqual(memory.peak?.id, "01")
        XCTAssertEqual(memory.storyPhotos.first?.isPeak, true)
    }

    /// Photos at 14:00, 14:01... in the order given; `peak` flagged.
    static func memory(ids: [String], peak: String?) -> TriggerMemory {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let ordered = ids.sorted()
        let photos = ids.map { id in
            TriggerMemory.Photo(
                id: id, takenAt: start.addingTimeInterval(Double(ordered.firstIndex(of: id) ?? 0) * 60),
                isPeak: id == peak
            )
        }
        return TriggerMemory(
            id: "m", date: "2025-10-09", daypart: .afternoon,
            push: .init(title: "t", body: "b", coverPhotoId: peak ?? "01"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "f", detail: "", question: "q", questionId: "B1", ctaLabel: "c")
        )
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
        let byID = Dictionary(uniqueKeysWithValues: memory.storyPhotos.map { ($0.id, $0) })
        XCTAssertNotNil(loader.url(for: try XCTUnwrap(byID["01"])))
        XCTAssertNil(loader.url(for: try XCTUnwrap(byID["02"])), "02.jpg was never written")
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
            for (cell, frame) in all.enumerated() {
                XCTAssertTrue(card.contains(frame), "cell \(cell) of \(count) leaves the card")
                for other in all[(cell + 1)...] {
                    XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other), "cells overlap at \(count)")
                }
            }
        }
    }

    func testShortScreensCapTheTopCell() {
        XCTAssertEqual(TriggerGridLayout(photoCount: 3, width: 360, maxBigHeight: 120).big.height, 120)
    }
}
