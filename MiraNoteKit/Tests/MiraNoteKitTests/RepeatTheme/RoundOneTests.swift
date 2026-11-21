import Foundation
import XCTest
@testable import MiraNoteKit

final class RoundOneTests: XCTestCase {
    private let facts = WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20,
                                   weekpart: "weekday", places: nil)
    private let center = GeoPoint(lat: 31.2, lon: 121.4)

    private func group(_ id: String, days: Int = 5, center: GeoPoint? = nil) -> SplitGroup {
        SplitGroup(id: id, key: "k\(id)", momentIds: ["m\(id)"], days: days, where: facts, placeCenter: center)
    }

    private var offered: (a: [SplitGroup], b: [SplitGroup]) {
        ([group("A1"), group("A2")], [group("B1", center: center), group("B2")])
    }

    private func answer(_ json: String) -> RoundOneAnswer {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(RoundOneAnswer.self, from: Data(json.utf8))
    }

    private func validate(_ json: String) -> Result<RoundOneAnswer, RoundOneProblem> {
        RoundOneValidator.validate(answer(json), offered: offered)
    }

    private func problem(_ json: String) -> RoundOneProblem? {
        if case .failure(let problem) = validate(json) { return problem }
        return nil
    }

    // MARK: - Validation

    func testImageNumberInFromFails() {
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["7"],"name":"x"}]}"#), .imageNumberInFrom)
        let json = #"{"chosen":"A","groups":[{"from":["\u56FE7"],"name":"x"}]}"#
        XCTAssertEqual(problem(json), .imageNumberInFrom)
    }

    func testGroupInTwoGroupsFails() {
        let json = #"{"chosen":"A","groups":[{"from":["A1"],"name":"x"},{"from":["A2","A1"],"name":"y"}]}"#
        XCTAssertEqual(problem(json), .groupUsedTwice)
    }

    func testGroupOfOtherSplitFails() {
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["B1"],"name":"x"}]}"#), .groupFromOtherSplit)
    }

    func testUnknownGroupFails() {
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["A9"],"name":"x"}]}"#), .unknownGroup)
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["A0"],"name":"x"}]}"#), .unknownGroup)
    }

    func testEmptyFromOrBlankNameFails() {
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":[],"name":"x"}]}"#), .unknownGroup)
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"name":"x"}]}"#), .unknownGroup)
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["A1"],"name":" "}]}"#), .unknownGroup)
        XCTAssertEqual(problem(#"{"chosen":"A","groups":[{"from":["A1"]}]}"#), .unknownGroup)
    }

    func testValidAnswerPasses() throws {
        let json = #"{"chosen":"B","groups":[{"from":["B1"],"name":"x"},{"from":["B2"],"name":"y"}]}"#
        XCTAssertEqual(try validate(json).get().groups.count, 2)
    }

    func testEvidenceIgnoredWhenChosenB() throws {
        let json = #"{"chosen":"B","groups":[{"from":["B1"],"name":"x","evidence":["soup"]}]}"#
        XCTAssertEqual(try validate(json).get().groups[0].evidence, [])
        let keep = #"{"chosen":"A","groups":[{"from":["A1"],"name":"x","evidence":["soup"]}]}"#
        XCTAssertEqual(try validate(keep).get().groups[0].evidence, ["soup"])
    }

    func testUnknownDropGroupsIgnored() throws {
        let json = #"{"chosen":"A","groups":[{"from":["A1"],"name":"x"}],"drop_groups":["A0","B2","A2","A7"]}"#
        XCTAssertEqual(try validate(json).get().dropGroups, ["A2"])
    }

    func testSensitiveSkipsGroupChecks() throws {
        let json = #"{"sensitive":true,"chosen":"A","groups":[{"from":["7"],"name":"x"}]}"#
        XCTAssertTrue(try validate(json).get().sensitive)
    }

    func testChosenNoneIgnoresGroups() throws {
        let json = #"{"chosen":"none","groups":[{"from":["7"],"name":"x"}],"drop_groups":["A1"]}"#
        let result = try validate(json).get()
        XCTAssertEqual(result.groups, [])
        XCTAssertEqual(result.dropGroups, [])
    }

    func testUnknownChosenFails() {
        XCTAssertEqual(problem(#"{"chosen":"C","groups":[]}"#), .notJSON)
    }

    // MARK: - Shortening

    func testNameElevenCharactersNeedsShortening() {
        let long = String(repeating: "a", count: 11)
        let ten = String(repeating: "a", count: 10)
        let items = RoundOneValidator.tooLong(answer(
            #"{"chosen":"A","pile_name":"\#(long)","groups":[{"from":["A1","A2"],"name":"\#(long)","same_part":"s"},"#
            + #"{"from":["B1"],"name":"\#(ten)","same_part":"s"}]}"#))
        XCTAssertEqual(items.map(\.key), ["pile", "A1"])
        XCTAssertEqual(items[0].samePart, "")
        XCTAssertEqual(items[1].samePart, "s")
    }

    func testSamePartTwentyCharactersOK() {
        let twenty = String(repeating: "\u{FF0C}", count: 20)
        let items = RoundOneValidator.tooLong(answer(
            #"{"chosen":"A","groups":[{"from":["A1"],"name":"x","same_part":"\#(twenty)"}]}"#))
        XCTAssertEqual(items, [])
        let tooMany = RoundOneValidator.tooLong(answer(
            #"{"chosen":"A","groups":[{"from":["A1"],"name":"x","same_part":"\#(twenty)!"}]}"#))
        XCTAssertEqual(tooMany.map(\.key), ["A1"])
    }

    func testShortenItemEncodesSnakeCase() throws {
        let data = try JSONEncoder().encode(ShortenItem(key: "pile", name: "n", samePart: "s"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["key": "pile", "name": "n", "same_part": "s"])
    }

    // MARK: - Parsing

    func testUnparseableTextIsNotJSON() {
        XCTAssertEqual(RoundOneAnswer.parse("sorry, I cannot").failureValue, .notJSON)
        XCTAssertEqual(RoundOneAnswer.parse("{\"chosen\": ").failureValue, .notJSON)
        XCTAssertEqual(RoundOneAnswer.parse("").failureValue, .notJSON)
    }

    func testFencedAndSurroundedJSONParses() throws {
        let text = "Here you go:\n```json\n{\"chosen\":\"A\",\"pile_name\":\"a } b\",\"not_in_pile\":[3],"
            + "\"two_kinds\":true,\"groups\":[{\"from\":[\"A1\"],\"name\":\"x\"}]}\n```\nHope it helps {not json}"
        let parsed = try RoundOneAnswer.parse(text).get()
        XCTAssertEqual(parsed.pileName, "a } b")
        XCTAssertEqual(parsed.notInPile, [3])
        XCTAssertTrue(parsed.twoKinds)
        XCTAssertEqual(parsed.groups[0].from, ["A1"])
    }

    func testMissingFieldsDecodeLeniently() throws {
        let parsed = try RoundOneAnswer.parse("{}").get()
        XCTAssertFalse(parsed.sensitive)
        XCTAssertEqual(parsed.chosen, "none")
        XCTAssertNil(parsed.pileName)
        XCTAssertEqual(parsed.groups, [])
        XCTAssertEqual(parsed.dropGroups, [])
        XCTAssertEqual(parsed.notInPile, [])
    }

    // MARK: - Request

    private func sampled(_ index: Int, groupA: String, groupB: String) -> SampledPhoto {
        SampledPhoto(momentId: "m\(index)", photoId: "p\(index)", a: groupA, b: groupB)
    }

    private func moment(_ id: String, photos: Int = 1, labels: [(String, Float)]) -> Moment {
        Moment(id: id, photoIds: (0..<photos).map { "\(id)-\($0)" }, day: "2027-01-04",
               start: Date(timeIntervalSince1970: 0), vector: [1],
               labels: labels.map { LabelScore(id: $0.0, confidence: $0.1) }, location: center)
    }

    private func request(old: RoundOneRequest.Old? = nil) -> RoundOneRequest {
        let pile = Pile(momentIds: ["m1", "m2", "m3"], days: 3, maxDayShare: 0.4, height: 0.3, center: [1])
        let labels: [(String, Float)] = (0..<10).map { ("l\($0)", Float(10 - $0) / 10) } + [("weak", 0.1)]
        let moments = ["m1": moment("m1", photos: 3, labels: labels),
                       "m2": moment("m2", labels: [("soup", 0.5)])]
        return RoundOneRequest.make(pile: pile, moments: moments, a: offered.a, b: offered.b,
                                    photos: [sampled(1, groupA: "A1", groupB: "B1"),
                                             sampled(2, groupA: "A0", groupB: "B2")],
                                    old: old)
    }

    private func encoded(_ request: RoundOneRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestEncodesBackendShape() throws {
        let json = try encoded(request())
        XCTAssertEqual(Set(json.keys), ["pile", "split_a", "split_b", "photos", "old"])
        XCTAssertTrue(json["old"] is NSNull)
        XCTAssertEqual(json["pile"] as? [String: Int], ["photo_count": 5, "day_count": 3])
        let splitA = try XCTUnwrap(json["split_a"] as? [[String: Any]])
        XCTAssertEqual(splitA.map { $0["id"] as? String }, ["A1", "A2"])
        XCTAssertEqual(Set(splitA[0].keys), ["id", "days", "where"])
        let whereJSON = try XCTUnwrap(splitA[0]["where"] as? [String: Any])
        XCTAssertEqual(Set(whereJSON.keys), ["daypart", "daypart_share", "hour_from", "hour_to", "weekpart", "places"])
        XCTAssertTrue(whereJSON["places"] is NSNull)
        let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
        XCTAssertEqual(photos.map { $0["n"] as? Int }, [1, 2])
        XCTAssertEqual(Set(photos[0].keys), ["n", "a", "b", "labels"])
        XCTAssertEqual(photos[1]["a"] as? String, "A0")
    }

    func testRequestLabelsArePresentTopEightByConfidence() throws {
        let photos = try XCTUnwrap(encoded(request())["photos"] as? [[String: Any]])
        XCTAssertEqual(photos[0]["labels"] as? [String], (0..<8).map { "l\($0)" })
        XCTAssertEqual(photos[1]["labels"] as? [String], ["soup"])
    }

    func testRequestKeepsPhotoIdsOffTheWire() throws {
        let built = request()
        XCTAssertEqual(built.photoIds, [1: "p1", 2: "p2"])
        XCTAssertNil(try encoded(built)["photoIds"])
    }

    func testRequestEncodesOld() throws {
        let json = try encoded(request(old: .init(pileName: "dinner", groups: ["soup", "noodles"])))
        XCTAssertEqual(json["old"] as? [String: AnyHashable],
                       ["pile_name": "dinner", "groups": ["soup", "noodles"]])
    }

    func testRequestHasNoCoordinates() throws {
        let data = try JSONEncoder().encode(request())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()
        for key in ["latitude", "longitude", "\"lat\"", "\"lon\"", "placecenter", "center"] {
            XCTAssertFalse(text.contains(key), key)
        }
        XCTAssertFalse(text.contains("31.2"))
        XCTAssertFalse(text.contains("121.4"))
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
