import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import MiraNoteKit

/// The rounds contract (`POST /collections/rounds/1`, `/2`, `/shorten`) over
/// the app's HTTP client, and what the images look like on the wire (D3, M2).
final class ThemeRoundClientTests: XCTestCase {
    private let base = URL(string: "http://localhost:8006")!

    private var client: LiveThemeRoundClient {
        LiveThemeRoundClient(baseURL: base,
                             http: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "token"))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private static let okBody = #"""
    {"status": "ok", "reply": "{\"chosen\": \"none\", \"pile_name\": \"Meals\"}",
     "where": {"A1": "evening", "B1": "home"},
     "usage": {"prompt_tokens": 1978, "completion_tokens": 248, "cost_cny": 0.00059, "model": "qwen3.7-flash"}}
    """#

    /// Answers every request with `status` and `body`; the last request is kept.
    private func respond(_ status: Int, _ body: String) -> RequestBox {
        let box = RequestBox()
        StubURLProtocol.handler = { request in
            box.request = request
            box.body = request.capturedBody
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        return box
    }

    private var request: RoundOneRequest {
        let facts = WhereFacts(daypart: "evening", daypartShare: 0.8, hourFrom: 18, hourTo: 20, weekpart: "weekday",
                               places: 1)
        let group = SplitGroup(id: "A1", key: "food", momentIds: ["m1", "m2"], days: 2, where: facts,
                               placeCenter: GeoPoint(lat: 31.2, lon: 121.4))
        let moments = ["m1", "m2"].enumerated().map { offset, id in
            Moment(id: id, photoIds: [id], day: "d\(offset)",
                   start: Date(timeIntervalSince1970: Double(offset) * 86_400),
                   vector: [1, 0], labels: [LabelScore(id: "food", confidence: 0.9)], location: nil)
        }
        let pile = Pile(momentIds: ["m1", "m2"], days: 2, maxDayShare: 0.5, height: 0.1, center: [1, 0])
        let photos = [SampledPhoto(momentId: "m1", photoId: "m1", a: "A1", b: "B0"),
                      SampledPhoto(momentId: "m2", photoId: "m2", a: "A1", b: "B0")]
        return RoundOneRequest.make(pile: pile, moments: Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) }),
                                    a: [group], b: [], photos: photos, old: nil)
    }

    func testRoundOneMultipartShapeAndAuth() async throws {
        let box = respond(200, Self.okBody)
        let reply = try await client.roundOne(request, images: [(n: 1, jpeg: Data("one".utf8)),
                                                                (n: 2, jpeg: Data("two".utf8))])
        XCTAssertEqual(reply.reply, #"{"chosen": "none", "pile_name": "Meals"}"#)
        XCTAssertEqual(reply.where, ["A1": "evening", "B1": "home"])
        XCTAssertEqual(reply.usage, RoundUsage(promptTokens: 1978, completionTokens: 248, costCny: 0.00059,
                                               model: "qwen3.7-flash"))

        let sent = try XCTUnwrap(box.request)
        XCTAssertEqual(sent.url?.path, "/collections/rounds/1")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        let type = try XCTUnwrap(sent.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(type.hasPrefix("multipart/form-data; boundary="))
        XCTAssertLessThan(sent.timeoutInterval, 125, "under the tunnel's limit")
        let body = try XCTUnwrap(String(bytes: try XCTUnwrap(box.body), encoding: .utf8))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="meta""#))
        XCTAssertTrue(body.contains(#""split_a":[{"#))
        XCTAssertTrue(body.contains(#""photo_count":2"#))
        XCTAssertTrue(body.contains(#"name="photos"; filename="1.jpg""#))
        XCTAssertTrue(body.contains(#"name="photos"; filename="2.jpg""#))
        XCTAssertTrue(body.contains("one") && body.contains("two"))
        for word in ["lat", "lon", "place_center", "placeCenter", "121.4"] {
            XCTAssertFalse(body.contains(word), "no coordinates: \(word)")
        }
    }

    func testRoundTwoPostsItsMeta() async throws {
        let box = respond(200, Self.okBody)
        let meta = RoundTwoRequest(theme: .init(name: "Meals", noun: "", samePart: "bowl"),
                                   photos: [.init(n: 1)], pushed: ["Sky"], blocked: [])
        _ = try await client.roundTwo(meta, images: [(n: 1, jpeg: Data("one".utf8))])
        XCTAssertEqual(box.request?.url?.path, "/collections/rounds/2")
        let body = try XCTUnwrap(String(bytes: try XCTUnwrap(box.body), encoding: .utf8))
        XCTAssertTrue(body.contains(#""theme":{"name":"Meals","noun":"","same_part":"bowl"}"#))
        XCTAssertTrue(body.contains(#""photos":[{"n":1}]"#))
        XCTAssertTrue(body.contains(#""pushed":["Sky"]"#))
        XCTAssertTrue(body.contains(#""blocked":[]"#))
    }

    func testShortenPostsJSONItems() async throws {
        let box = respond(200, Self.okBody)
        _ = try await client.shorten([ShortenItem(key: "pile", name: "Abcdefghijk", samePart: "")])
        let sent = try XCTUnwrap(box.request)
        XCTAssertEqual(sent.url?.path, "/collections/rounds/shorten")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(box.body)) as? [String: Any])
        let items = try XCTUnwrap(object["items"] as? [[String: String]])
        XCTAssertEqual(items, [["key": "pile", "name": "Abcdefghijk", "same_part": ""]])
    }

    func test502MapsToRoundError() async {
        _ = respond(502, #"{"status": "error", "reason": "timeout", "usage": {"prompt_tokens": 0,"#
                    + #" "completion_tokens": 0, "cost_cny": 0.0, "model": "qwen3.7-flash"}}"#)
        do {
            _ = try await client.roundOne(request, images: [(n: 1, jpeg: Data("one".utf8))])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ThemeRoundError,
                           .model(reason: "timeout", usage: RoundUsage(promptTokens: 0, completionTokens: 0,
                                                                       costCny: 0, model: "qwen3.7-flash")))
        }
    }

    func testOtherFailuresMap() async {
        _ = respond(401, "")
        do {
            _ = try await client.shorten([ShortenItem(key: "pile", name: "x", samePart: "")])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ThemeRoundError, .unauthorized)
        }
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await client.shorten([ShortenItem(key: "pile", name: "x", samePart: "")])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ThemeRoundError, .unreachable)
        }
    }

    func testEndedSignInMapsToUnauthorized() async {
        _ = respond(200, Self.okBody)
        let signedOut = LiveThemeRoundClient(
            baseURL: base, http: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "token",
                                            userTokens: EndedSignIn()))
        do {
            _ = try await signedOut.shorten([ShortenItem(key: "pile", name: "x", samePart: "")])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ThemeRoundError, .unauthorized)
        }
    }

    /// The engine's images as they reach the backend: a 2000 x 1500 photo with
    /// GPS, EXIF and TIFF goes out 336 px on its long side and bare.
    func testImagesAre336AndCarryNoMetadata() async throws {
        let harness = ThemeHarness()
        harness.addTheme("x", base: 0, days: Array(1...6))
        let original = try ComposeMetaTests.jpegWithGPS(width: 2000, height: 1500)
        harness.imageData = { _ in original }
        harness.roundClient = client
        let box = respond(200, Self.okBody)
        let report = await harness.engine().run(trigger: .debug, deadline: nil)
        XCTAssertEqual(report.asked, 1)

        let body = try XCTUnwrap(box.body)
        let type = try XCTUnwrap(box.request?.value(forHTTPHeaderField: "Content-Type"))
        let boundary = String(try XCTUnwrap(type.components(separatedBy: "boundary=").last))
        let images = Self.fileParts(body, boundary: boundary)
        XCTAssertEqual(images.keys.sorted(), (1...6).map { "\($0).jpg" })
        for (name, jpeg) in images {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil), name)
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
            let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
            XCTAssertEqual(max(width, height), 336, name)
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary], name)
            XCTAssertNil(properties[kCGImagePropertyTIFFDictionary], name)
            // ImageIO reports what it reads off the JPEG itself; nothing came from the photo.
            let exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
            let derived: Set<CFString> = [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension,
                                          kCGImagePropertyExifPixelYDimension]
            XCTAssertTrue(Set(exif.keys).isSubset(of: derived), "\(name): \(exif.keys)")
        }
    }

    /// The file parts of a multipart body by file name.
    private static func fileParts(_ body: Data, boundary: String) -> [String: Data] {
        let marker = Data("--\(boundary)".utf8)
        let headerEnd = Data("\r\n\r\n".utf8)
        var parts: [String: Data] = [:]
        var cursor = body.startIndex
        while let found = body.range(of: marker, in: cursor..<body.endIndex) {
            let start = found.upperBound
            guard let next = body.range(of: marker, in: start..<body.endIndex) else { break }
            cursor = next.lowerBound
            guard let split = body.range(of: headerEnd, in: start..<next.lowerBound) else { continue }
            let headers = String(bytes: body[start..<split.lowerBound], encoding: .utf8) ?? ""
            guard let nameRange = headers.range(of: #"filename="[^"]+""#, options: .regularExpression) else { continue }
            let name = headers[nameRange].dropFirst("filename=\"".count).dropLast()
            parts[String(name)] = body[split.upperBound..<(next.lowerBound - 2)]  // drop the CRLF before the marker
        }
        return parts
    }
}

/// A sign-in whose tokens are gone.
private struct EndedSignIn: UserTokenSource {
    func accessTokenIfSignedIn() async throws -> String? { throw AccountError.signedOut }
    func renewAccessToken(after rejected: String) async throws -> String { throw AccountError.signedOut }
    func endSignIn(refused token: String) {}
}

private final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
    var body: Data?
}
