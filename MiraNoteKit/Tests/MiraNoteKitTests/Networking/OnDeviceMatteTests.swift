import XCTest
@testable import MiraNoteKit

/// A matte that answers however the test needs, without touching Vision.
/// `failing` is the interesting one: "no salient subject" is an ordinary
/// outcome for a landscape or a flat backdrop, not a malfunction.
private struct StubMatte: ForegroundMatte {
    var output: Data = Data("lifted".utf8)
    var failEvery: ((Int) -> Bool)?
    final class Counter: @unchecked Sendable { var calls = 0 }
    let counter = Counter()

    func removeBackground(_ image: Data) throws -> Data {
        let index = counter.calls
        counter.calls += 1
        if failEvery?(index) == true { throw ForegroundMatteError.noSubject }
        return output
    }
}

final class OnDeviceMatteRoutingTests: XCTestCase {
    private let tiny = MockImageStudioService.tinyPNG.base64EncodedString()

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service(matte: ForegroundMatte?) -> LiveImageStudioService {
        LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            matte: matte
        )
    }

    private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200,
                         httpVersion: nil, headerFields: nil)!, Data(json.utf8))
    }

    // MARK: - Cutout

    func testPlainCutoutNeverReachesTheNetwork() async throws {
        // The point of the whole change: this works with the backend off.
        StubURLProtocol.handler = { request in
            XCTFail("a targetless cutout must not call the server")
            return self.ok(#"{"image": "\#(self.tiny)"}"#, for: request)
        }
        let matte = StubMatte()

        let out = try await service(matte: matte).cutout(image: Data("photo".utf8), target: nil)

        XCTAssertEqual(out, Data("lifted".utf8))
        XCTAssertEqual(matte.counter.calls, 1)
    }

    func testTargetedCutoutStillGoesToTheServer() async throws {
        // Vision is ~3% of that pipeline; GroundingDINO and SAM are the rest
        // and are far too large to ship in an app.
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"image": "\#(self.tiny)", "mode_used": "hybrid_sam_prebg_vision"}"#,
                           for: request)
        }
        let matte = StubMatte()

        let out = try await service(matte: matte)
            .cutout(image: Data("photo".utf8), target: "the boy on the left")

        XCTAssertEqual(out, MockImageStudioService.tinyPNG)
        XCTAssertEqual(captured?.url?.path, "/cutout")
        XCTAssertEqual(matte.counter.calls, 0, "the device matte has no say on this path")
    }

    func testWithoutAMatteEveryCutoutIsRemote() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"image": "\#(self.tiny)", "mode_used": "vision"}"#, for: request)
        }

        _ = try await service(matte: nil).cutout(image: Data("photo".utf8), target: nil)

        XCTAssertEqual(captured?.url?.path, "/cutout",
                       "no matte means the old behaviour, unchanged")
    }

    // MARK: - Sticker generation

    func testStickerGenerationAsksTheServerToSkipItsMatte() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"images": ["\#(self.tiny)", "\#(self.tiny)"], "count": 2}"#,
                           for: request)
        }
        let matte = StubMatte()

        let batch = try await service(matte: matte).generateStickers(prompt: "a sleepy cafe cat")

        let body = try JSONSerialization.jsonObject(with: captured!.capturedBody!) as? [String: Any]
        XCTAssertEqual(body?["matte"] as? String, "none",
                       "the server should not spend Vision calls the phone is about to make")
        XCTAssertEqual(body?["command"] as? String, "sticker")
        XCTAssertEqual(batch.images, [Data("lifted".utf8), Data("lifted".utf8)])
        XCTAssertTrue(batch.allMatted)
        XCTAssertEqual(matte.counter.calls, 2, "one per generated image")
    }

    func testAnImageThatCannotBeLiftedIsKeptAsItIs() async throws {
        // It is already drawn and already paid for. Discarding it over a
        // background is the mistake the server side just stopped making.
        StubURLProtocol.handler = { request in
            self.ok(#"{"images": ["\#(self.tiny)", "\#(self.tiny)"], "count": 2}"#, for: request)
        }
        var matte = StubMatte()
        matte.failEvery = { $0 == 0 }

        let batch = try await service(matte: matte).generateStickers(prompt: "a flat grey wall")

        XCTAssertEqual(batch.images.count, 2, "both pictures survive")
        XCTAssertEqual(batch.images[0], MockImageStudioService.tinyPNG,
                       "the one that failed comes back with its background")
        XCTAssertEqual(batch.images[1], Data("lifted".utf8))
        XCTAssertEqual(batch.unmatted, [0])
        XCTAssertFalse(batch.allMatted)
    }

    func testEveryImageFailingIsStillNotAnError() async throws {
        StubURLProtocol.handler = { request in
            self.ok(#"{"images": ["\#(self.tiny)", "\#(self.tiny)"], "count": 2}"#, for: request)
        }
        var matte = StubMatte()
        matte.failEvery = { _ in true }

        let batch = try await service(matte: matte).generateStickers(prompt: "an empty sky")

        XCTAssertEqual(batch.unmatted, [0, 1])
        XCTAssertEqual(batch.images.count, 2)
    }

    func testGenerateStillReturnsPlainImages() async throws {
        // The protocol's older entry point keeps working for callers that
        // only want pictures -- it just goes through the device matte now.
        StubURLProtocol.handler = { request in
            self.ok(#"{"images": ["\#(self.tiny)"], "count": 1}"#, for: request)
        }
        let matte = StubMatte()

        let images = try await service(matte: matte).generate(kind: .sticker, prompt: "a cat")

        XCTAssertEqual(images, [Data("lifted".utf8)])
    }

    func testNonStickerKindsAreUntouched() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"images": ["\#(self.tiny)"], "count": 1}"#, for: request)
        }
        let matte = StubMatte()

        let images = try await service(matte: matte).generate(kind: .background, prompt: "dusk")

        let body = try JSONSerialization.jsonObject(with: captured!.capturedBody!) as? [String: Any]
        XCTAssertNil(body?["matte"], "only stickers are ever matted, on either machine")
        XCTAssertEqual(images, [MockImageStudioService.tinyPNG])
        XCTAssertEqual(matte.counter.calls, 0)
    }

    func testWithoutAMatteStickersComeBackCutByTheServer() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"images": ["\#(self.tiny)"], "count": 1}"#, for: request)
        }

        let batch = try await service(matte: nil).generateStickers(prompt: "a cat")

        let body = try JSONSerialization.jsonObject(with: captured!.capturedBody!) as? [String: Any]
        XCTAssertNil(body?["matte"], "the server keeps its own default")
        XCTAssertTrue(batch.allMatted)
        XCTAssertEqual(batch.images, [MockImageStudioService.tinyPNG])
    }

    func testMockServiceGetsTheDefaultBatch() async throws {
        let batch = try await MockImageStudioService().generateStickers(prompt: "a cat")
        XCTAssertEqual(batch.images.count, 2)
        XCTAssertTrue(batch.allMatted, "a server-matted service reports nothing left over")
    }
}

/// The real Vision path, on inputs whose answer cannot drift.
///
/// Deliberately no "and it cuts out a cat" case: whether Vision finds a
/// particular subject is a property of the model, not of this code, and
/// pinning it would make the suite fail on an OS update. What this code owns
/// is the decoding, the error mapping, and the PNG on the way out.
final class VisionForegroundMatteTests: XCTestCase {
    private func solidPNG(_ size: Int = 200) throws -> Data {
        let context = CIContext()
        let image = CIImage(color: CIColor(red: 0.47, green: 0.55, blue: 0.63))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let png = context.pngRepresentation(of: image, format: .RGBA8,
                                            colorSpace: CGColorSpaceCreateDeviceRGB())
        return try XCTUnwrap(png)
    }

    func testAFlatImageReportsNoSubjectRatherThanFailing() throws {
        // This is the case the whole failure design exists for: a landscape,
        // a plain backdrop, an already-cut-out sticker. It must arrive as
        // .noSubject so callers can show the picture and say so.
        XCTAssertThrowsError(try VisionForegroundMatte().removeBackground(solidPNG())) {
            XCTAssertEqual($0 as? ForegroundMatteError, .noSubject)
        }
    }

    func testNonImageBytesAreReportedAsUndecodable() {
        XCTAssertThrowsError(
            try VisionForegroundMatte().removeBackground(Data("not a picture".utf8))
        ) {
            XCTAssertEqual($0 as? ForegroundMatteError, .undecodable)
        }
    }
}
