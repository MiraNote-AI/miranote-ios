import XCTest
@testable import MiraNoteKit

/// The repeat compose meta as backend Task 3 takes it, and the life
/// fragment's submit left as it was.
final class RepeatComposeMetaTests: XCTestCase {
    func testRepeatMetaShape() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let base = Date(timeIntervalSince1970: 1_793_000_000)  // 2026-10-26 07:33:20 UTC
        let photos = (0..<5).map { index in
            ThemePhoto(id: "local-\(index)", takenAt: base.addingTimeInterval(Double(index) * 86_400), location: nil,
                       labels: [LabelScore(id: "food", confidence: 0.9),
                                LabelScore(id: "unknown_label", confidence: 1)],
                       aesthetics: 0.5, faces: index == 1 ? 2 : 0, isTheme: true, print: Data(), printRevision: 1)
        }
        let library = Dictionary(uniqueKeysWithValues: photos.map {
            ($0.id, LibraryAsset(id: $0.id, takenAt: $0.takenAt, location: GeoPoint(lat: 31.2, lon: 121.5),
                                 isFavorite: $0.id == "local-0", isEdited: $0.id == "local-4", isScreenshot: false,
                                 isHidden: false, isVideo: false, originalFilename: nil, burstId: nil))
        })
        let row = ThemeRow(id: "soup", kind: .small, parentId: "big", name: "Soup", noun: "soup", samePart: "a bowl",
                           split: "A", status: .active, center: nil, rule: .content(evidence: ["soup"]),
                           members: photos.map(\.id), lastAskedCount: 5, flagged: false, followRatio: nil,
                           where: WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20,
                                             weekpart: "weekday", places: 1))
        let built = RepeatComposeMeta.build(theme: row, photoIds: photos.map(\.id).reversed(),
                                            photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }),
                                            library: library, recentQuestionTypes: ["order"], calendar: calendar)
        XCTAssertEqual(built.photoIds, Dictionary(uniqueKeysWithValues: (0..<5).map { ("P\($0 + 1)", "local-\($0)") }))
        let json = try XCTUnwrap(String(bytes: try built.meta.encoded(), encoding: .utf8))
        func photo(_ number: Int, _ day: Int, faces: Int = 0, favorite: Bool = false, edited: Bool = false) -> String {
            #"{"edited":\#(edited),"faces":\#(faces),"favorite":\#(favorite),"id":"P\#(number)","#
                + #""labels":["food_drink"],"taken_at":"2026-10-\#(day)T15:33:20+08:00"}"#
        }
        let sent: [String] = [photo(1, 26, favorite: true), photo(2, 27, faces: 2), photo(3, 28), photo(4, 29),
                              photo(5, 30, edited: true)]
        let theme = #""theme":{"id":"soup","name":"Soup","noun":"soup","same_part":"a bowl","#
            + #""where":{"daypart":"evening","daypart_share":0.8,"hour_from":18,"hour_to":20,"places":1,"#
            + #""weekpart":"weekday"}}"#
        let head = #"{"group_key":"\#(built.meta.groupKey)","mode":"repeat","photos":["#
        let tail = #"],"recent_question_types":["order"],"# + theme + #","tz":"Asia/Shanghai"}"#
        let expected: String = head + sent.joined(separator: ",") + tail
        XCTAssertEqual(json, expected)
        XCTAssertTrue(built.meta.groupKey.hasPrefix("repeat_"))
        XCTAssertFalse(json.contains("31.2") || json.contains("121.5"), "no coordinates")

        // A big theme has no where: an explicit null.
        let bigOne = RepeatComposeMeta.build(theme: ThemeHarness.row("big", name: "Dinner", members: [], lastAsked: 0,
                                                                             center: []), photoIds: photos.map(\.id),
                                             photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }),
                                             library: library, recentQuestionTypes: [], calendar: calendar)
        let bigJSON = try XCTUnwrap(String(bytes: try bigOne.meta.encoded(), encoding: .utf8))
        XCTAssertTrue(bigJSON.contains(#""where":null"#), bigJSON)
    }

    /// The life-fragment meta goes out as it always did: the same bytes
    /// whether given as a `ComposeMeta` or already encoded.
    func testLifeFragmentSubmitUnchanged() async throws {
        let bodies = BodyLog()
        StubURLProtocol.handler = { request in
            bodies.add(request.capturedBody ?? Data())
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"job_id": "job-1"}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let live = LiveComposeClient(http: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "token"),
                                     baseURL: URL(string: "http://localhost:8006")!)
        let meta = ComposeMeta(groupKey: "k", date: "2026-10-18", weekday: 7, startTime: "14:03", endTime: "15:00",
                               place: nil, rawCount: 3, coversAll: true, recentQuestionTypes: [], bucket: "food",
                               tz: "UTC", photos: [])
        _ = try await live.submit(meta, photos: [(id: "P1", jpeg: Data("one".utf8))])
        _ = try await live.submit(metaJSON: try meta.encoded(), photos: [(id: "P1", jpeg: Data("one".utf8))])
        let parts = bodies.all.map(Self.metaPart)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], try meta.encoded())
        XCTAssertEqual(parts[0], parts[1])
    }

    /// The bytes of a multipart body's `meta` part.
    private static func metaPart(_ body: Data) -> Data {
        let text = String(bytes: body, encoding: .utf8) ?? ""
        guard let header = text.range(of: "charset=utf-8\r\n\r\n"),
              let end = text.range(of: "\r\n--", range: header.upperBound..<text.endIndex) else { return Data() }
        return Data(text[header.upperBound..<end.lowerBound].utf8)
    }

    private final class BodyLog: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [Data] = []
        var all: [Data] { lock.withLock { bodies } }
        func add(_ body: Data) { lock.withLock { bodies.append(body) } }
    }
}
