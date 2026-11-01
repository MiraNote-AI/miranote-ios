import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MiraNoteKit

/// The photo-collections contract (handoff 5.1 / 5.2 plus the two gap
/// fills): the meta, the images, submit and poll.
final class ComposeMetaTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Chicago")!

    private func meta(place: String?) -> ComposeMeta {
        ComposeMeta(
            groupKey: "2026-10-18_8f3a0000", date: "2026-10-18", weekday: 6, startTime: "14:03", endTime: "17:40",
            place: place, rawCount: 23, coversAll: true, recentQuestionIds: ["B4", "A2"],
            photos: [.init(id: "P1", takenAt: "2026-10-18T14:03:00-05:00", labels: ["food_drink", "tableware"],
                           faces: 0, favorite: true, edited: false, represents: 1)]
        )
    }

    func testMetaEncodesSnakeCaseAndNullPlace() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: meta(place: nil).encoded()) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["group_key", "date", "weekday", "start_time", "end_time", "place",
                                          "raw_count", "covers_all", "recent_question_ids", "photos"])
        XCTAssertTrue(object["place"] is NSNull, "an unknown place is sent as null")
        let photo = try XCTUnwrap((object["photos"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(photo.keys), ["id", "taken_at", "labels", "faces", "favorite", "edited", "represents"])
        XCTAssertEqual(photo["taken_at"] as? String, "2026-10-18T14:03:00-05:00")
    }

    func testMetaHasNoCoordinates() throws {
        let text = try XCTUnwrap(String(bytes: try meta(place: "x").encoded(), encoding: .utf8))
        for word in ["lat", "lon", "location", "gps", "coordinate"] {
            XCTAssertFalse(text.lowercased().contains(word), word)
        }
    }

    func testMetaIsBuiltFromAFragment() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 14, minute: 3))!
        let photos = (0..<4).map {
            GroupablePhoto(id: "local-\($0)/L0/001", takenAt: start.addingTimeInterval(Double($0) * 1200),
                           location: GeoPoint(lat: 1, lon: 2), burstId: nil)
        }
        let fragment = Fragment(photos: photos, uniqueCount: 3, representative: ["local-1/L0/001": "local-0/L0/001"],
                                belongsTo: "2026-10-18")
        let picks = ["local-0/L0/001", "local-2/L0/001", "local-3/L0/001"].map {
            Preselected(id: $0, reason: .all, score: 0.5, represents: $0 == "local-0/L0/001" ? 2 : 1)
        }
        let first = PhotoAnalysis(id: "local-0/L0/001", labels: [], broad: [.tableware, .food_drink],
                                  faces: 1, aesthetics: nil, isUtility: false, featurePrint: nil)
        let analyses = ["local-0/L0/001": first]
        let built = ComposeMeta.build(fragment: fragment, picks: picks, analyses: analyses, library: [:],
                                      place: nil, recentQuestionIds: ["A1"], calendar: calendar)
        XCTAssertEqual(built.photoIds, ["P1": "local-0/L0/001", "P2": "local-2/L0/001", "P3": "local-3/L0/001"])
        let meta = built.meta
        XCTAssertTrue(meta.groupKey.hasPrefix("2026-10-18_"))
        XCTAssertEqual(meta.groupKey.count, "2026-10-18_".count + 8)
        XCTAssertEqual(meta.weekday, 7, "2026-10-18 is a Sunday: 1 is Monday")
        XCTAssertEqual(meta.startTime, "14:03")
        XCTAssertEqual(meta.endTime, "15:03")
        XCTAssertEqual(meta.rawCount, 4)
        XCTAssertTrue(meta.coversAll)
        XCTAssertEqual(meta.photos.map(\.id), ["P1", "P2", "P3"])
        XCTAssertEqual(meta.photos[0].labels, ["food_drink", "tableware"])
        XCTAssertEqual(meta.photos[0].represents, 2)
        XCTAssertEqual(meta.photos[1].takenAt, "2026-10-18T14:43:00-05:00")
        // Leaving a unique photo out: no longer covers all.
        let fewer = ComposeMeta.build(fragment: fragment, picks: Array(picks.prefix(2)), analyses: [:], library: [:],
                                      place: nil, recentQuestionIds: [], calendar: calendar)
        XCTAssertFalse(fewer.meta.coversAll)
    }

    func testUploadImageIsAtMost768AndHasNoGps() throws {
        let original = try Self.jpegWithGPS(width: 2000, height: 1500)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(original as CFData, nil))
        let before = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertNotNil(before?[kCGImagePropertyGPSDictionary], "the fixture really has GPS")

        let prepared = try XCTUnwrap(UploadImage.prepare(original))
        let out = try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(out, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(width, height), 768)
        XCTAssertEqual(CGImageSourceGetType(out) as String?, UTType.jpeg.identifier)
    }

    /// A small real JPEG, for fakes that upload.
    static let tinyJPEG: Data = {
        guard let data = try? jpegWithGPS(width: 40, height: 30) else { fatalError("no JPEG") }
        return data
    }()

    /// A JPEG carrying GPS, a capture date and a camera model.
    static func jpegWithGPS(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 32.82, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 96.72, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:18 14:03:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

final class LiveComposeClientTests: XCTestCase {
    private let base = URL(string: "http://localhost:8006")!

    private var client: LiveComposeClient {
        LiveComposeClient(http: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "token"), baseURL: base)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func respond(_ status: Int, _ body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
            return (response!, Data(body.utf8))
        }
    }

    private let meta = ComposeMeta(groupKey: "k", date: "2026-10-18", weekday: 7, startTime: "14:03", endTime: "15:00",
                                   place: nil, rawCount: 3, coversAll: true, recentQuestionIds: [], photos: [])

    func testSubmitBuildsMultipartWithMetaAndPhotos() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"job_id": "job-1"}"#.utf8))
        }
        let job = try await client.submit(meta, photos: [(id: "P1", jpeg: Data("one".utf8)),
                                                          (id: "P2", jpeg: Data("two".utf8))])
        XCTAssertEqual(job, "job-1")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.path, "/collections/compose")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(type.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(String(bytes: try XCTUnwrap(request.capturedBody), encoding: .utf8))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="meta""#))
        XCTAssertTrue(body.contains(#""group_key":"k""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="photos"; filename="P1.jpg""#))
        XCTAssertTrue(body.contains(#"name="photos"; filename="P2.jpg""#))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(body.contains("one") && body.contains("two"))
        XCTAssertLessThan(request.timeoutInterval, 125, "under the tunnel's limit")
    }

    func testPollParsesOkFixture() async throws {
        let fixture = try String(contentsOf: Fixtures.url("compose_ok.json"), encoding: .utf8)
        var path: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(fixture.utf8))
        }
        let status = try await client.poll("job-1")
        XCTAssertEqual(path, "/collections/jobs/job-1")
        guard case .ok(let memory) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(memory.ending.questionId, "A1")
        XCTAssertEqual(memory.peak?.id, "P9")
    }

    func testPollParsesRunning() async throws {
        respond(200, #"{"status": "running"}"#)
        let status = try await client.poll("job-1")
        XCTAssertEqual(status, .running)
    }

    func testPollParsesRejectedAndError() async throws {
        respond(200, #"{"status": "rejected", "reason": "too_few_selected", "message": "few"}"#)
        let rejected = try await client.poll("job-1")
        XCTAssertEqual(rejected, .rejected(reason: "too_few_selected", message: "few"))
        respond(200, #"{"status": "error", "reason": "timeout", "message": "slow"}"#)
        let failed = try await client.poll("job-1")
        XCTAssertEqual(failed, .failed(reason: "timeout", message: "slow"))
    }

    func test404IsExpired() async throws {
        respond(404, #"{"status": "expired"}"#)
        let status = try await client.poll("job-old")
        XCTAssertEqual(status, .expired)
    }

    func test429IsRateLimited() async {
        respond(429, #"{"detail": "slow down"}"#)
        do {
            _ = try await client.poll("job-1")
            XCTFail("expected rate limited")
        } catch {
            XCTAssertEqual(error as? ComposeError, .rateLimited)
        }
    }

    func testBadRequestCarriesTheMessage() async {
        respond(400, #"{"status": "error", "reason": "bad_request", "message": "no photos"}"#)
        do {
            _ = try await client.submit(meta, photos: [])
            XCTFail("expected bad request")
        } catch {
            XCTAssertEqual(error as? ComposeError, .badRequest("no photos"))
        }
    }

    func testUnreachableAndUnauthorized() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await client.poll("job-1")
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ComposeError, .unreachable)
        }
        respond(401, "")
        do {
            _ = try await client.poll("job-1")
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? ComposeError, .unauthorized)
        }
    }

    func testBetaAddressesAreFive() {
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.collections.absoluteString, "https://beta-collections.miranote.app")
        XCTAssertEqual(MiraNoteConfig.Backend.collectionsBaseURL.absoluteString, "http://localhost:8006")
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.all.count, 5)
    }
}
