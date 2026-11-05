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
        XCTAssertEqual(memory.ending.question, "What else?")
        XCTAssertEqual(memory.ending.questionType, "")
        XCTAssertEqual(memory.ending.questions.map(\.text), ["What else?"])
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
        XCTAssertEqual(memory.ending.questions.map(\.type), ["zoom", "sound", "route"])
        // Before a night picks: the backend's first.
        XCTAssertEqual(memory.ending.question, memory.ending.questions[0].text)
        XCTAssertEqual(memory.ending.questionType, "zoom")
        XCTAssertEqual(memory.ending.questionSource, "llm")
        XCTAssertEqual(memory.generation?.copyVersion, "copy_v3")
        XCTAssertFalse(memory.ending.detail.isEmpty)
        XCTAssertFalse(memory.bucket.isEmpty)
        XCTAssertEqual(memory.storyPhotos.map(\.id), ["P9", "P2"])
        XCTAssertNotNil(memory.facts["P9"])
        XCTAssertEqual(memory.generation?.latencyMs, 41000)
        XCTAssertNil(memory.story.photos[0].file)
    }

    /// A push saved before question types (`question` + `questionId`): the
    /// question is its one candidate, of no known type.
    func testPushSavedBeforeQuestionTypesDecodes() throws {
        let legacy = json.replacingOccurrences(of: #""question": "What else?","#,
                                               with: #""question": "What else?", "questionId": "A1","#)
        XCTAssertNotEqual(legacy, json)
        let memory = try TriggerMemory.decode(Data(legacy.utf8))
        XCTAssertEqual(memory.ending.question, "What else?")
        XCTAssertEqual(memory.ending.questionType, "")
        XCTAssertEqual(memory.ending.questionSource, "A1")
        XCTAssertEqual(memory.ending.otherQuestions, [])
        XCTAssertEqual(memory.generation?.copyVersion, nil)
    }

    /// An ending with neither a question nor candidates does not decode.
    func testEndingWithoutQuestionsIsAnError() {
        let bare = json.replacingOccurrences(of: #""question": "What else?","#, with: "")
        XCTAssertNotEqual(bare, json)
        XCTAssertThrowsError(try TriggerMemory.decode(Data(bare.utf8)))
    }

    /// A picked push saved and read back asks the same question and keeps
    /// every candidate.
    func testPickedEndingRoundTrips() throws {
        let data = try Data(contentsOf: Fixtures.url("compose_ok.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memoryData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object["memory"]))
        let answered = try TriggerMemory.decode(memoryData)
        let picked = answered.picking(answered.ending.questions[2])
        let back = try TriggerMemory.decode(TriggerMemory.encoder.encode(picked))
        XCTAssertEqual(back, picked)
        XCTAssertEqual(back.ending.questionType, "route")
        XCTAssertEqual(back.ending.questions.count, 3)
        XCTAssertEqual(back.ending.otherQuestions.map(\.type), ["zoom", "sound"])
    }

    /// The backend may add fields (generation.peakRewrite, .peakSwitched):
    /// they are ignored, never a decoding failure.
    func testUnknownFieldsAreIgnored() throws {
        let data = try Data(contentsOf: Fixtures.url("compose_ok.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var memory = try XCTUnwrap(object["memory"] as? [String: Any])
        var generation = try XCTUnwrap(memory["generation"] as? [String: Any])
        generation["peakRewrite"] = true
        generation["peakSwitched"] = false
        memory["generation"] = generation
        memory["somethingNew"] = ["x": 1]
        object["memory"] = memory
        let status = try LiveComposeClient.status(from: JSONSerialization.data(withJSONObject: object))
        guard case .ok(let decoded) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(decoded.generation?.model, "qwen3.7-flash")
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
            ending: .init(factLine: "f", detail: "",
                          questions: [.init(text: "q", type: "one_word", source: "fallback_B1")], ctaLabel: "c")
        )
    }

    func testDaypartBoundaries() {
        XCTAssertEqual([4, 5, 10, 11, 13, 14, 16, 17, 18, 19, 23, 0].map { Daypart(hour: $0) },
                       [.night, .morning, .morning, .noon, .noon, .afternoon, .afternoon,
                        .evening, .evening, .night, .night, .night])
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
