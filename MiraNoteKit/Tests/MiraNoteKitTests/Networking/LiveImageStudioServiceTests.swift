import XCTest
@testable import MiraNoteKit

final class LiveImageStudioServiceTests: XCTestCase {
    private func makeService() -> LiveImageStudioService {
        LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    func testGeneratePostsCommandAndDecodesImages() async throws {
        let tiny = MockImageStudioService.tinyPNG.base64EncodedString()
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"images": ["\#(tiny)", "\#(tiny)"], "count": 2}"#, for: request)
        }

        let images = try await makeService().generate(kind: .sticker, prompt: "a sleepy cafe cat")

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(captured?.url?.path, "/generate")
        let body = try JSONSerialization.jsonObject(with: captured!.capturedBody!) as? [String: Any]
        XCTAssertEqual(body?["command"] as? String, "sticker")
        XCTAssertEqual(body?["prompt"] as? String, "a sleepy cafe cat")
        XCTAssertEqual(body?["expand"] as? Bool, true)
        XCTAssertEqual(
            captured?.timeoutInterval, 180,
            "generation outlives URLSession's 60s default; the request must say so"
        )
    }

    func testCutoutUploadsFileWithTargetPrompt() async throws {
        let tiny = MockImageStudioService.tinyPNG.base64EncodedString()
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"image": "\#(tiny)", "mode_used": "auto"}"#, for: request)
        }

        let out = try await makeService().cutout(image: Data("img".utf8), target: "the cat")

        XCTAssertEqual(out, MockImageStudioService.tinyPNG)
        XCTAssertEqual(captured?.url?.path, "/cutout")
        XCTAssertTrue(captured?.url?.query?.contains("prompt=the%20cat") ?? false)
        let sent = String(data: captured!.capturedBody!, encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("name=\"file\""), "uploads a multipart file field")
        XCTAssertTrue(sent.contains("img"), "carries the image bytes")
    }

    func testCutoutTargetPlusSignStaysEncoded() async throws {
        let tiny = MockImageStudioService.tinyPNG.base64EncodedString()
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"image": "\#(tiny)", "mode_used": "auto"}"#, for: request)
        }

        _ = try await makeService().cutout(image: Data("img".utf8), target: "salt & pepper + C++")

        let wire = captured?.url?.absoluteString ?? ""
        XCTAssertTrue(
            wire.contains("salt%20%26%20pepper%20%2B%20C%2B%2B"),
            "separators stay escaped inside values and plus signs never decode to spaces; got \(wire)"
        )
    }

    func testOutlineRequestsOutlineMode() async throws {
        let tiny = MockImageStudioService.tinyPNG.base64EncodedString()
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return self.ok(#"{"image": "\#(tiny)", "mode_used": "outline"}"#, for: request)
        }

        _ = try await makeService().outline(image: Data("img".utf8))

        XCTAssertEqual(captured?.url?.path, "/border")
        XCTAssertTrue(captured?.url?.query?.contains("mode=outline") ?? false)
    }

    func testStylizeSendsInstructionAndMapsServerErrors() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("boom".utf8))
        }

        do {
            _ = try await makeService().stylize(image: Data("img".utf8), instruction: "remove the sign")
            XCTFail("expected a server error")
        } catch let error as BackendError {
            guard case .server(let status, _) = error else {
                return XCTFail("expected .server, got \(error)")
            }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("unexpected error type \(error)")
        }
    }
}

final class ImageFileStoreTests: XCTestCase {
    func testSaveRoundTripAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-store-test-\(UUID().uuidString)")
        let store = ImageFileStore(directory: dir)
        let id = UUID()

        let fileName = try store.save(Data("pixels".utf8), id: id)
        XCTAssertTrue(store.exists(fileName: fileName))
        XCTAssertEqual(store.data(forFileName: fileName), Data("pixels".utf8))

        store.delete(fileName: fileName)
        XCTAssertFalse(store.exists(fileName: fileName))
        try? FileManager.default.removeItem(at: dir)
    }
}

final class ImageModelCompatibilityTests: XCTestCase {
    func testLegacyImageRefAndStickerDecodeWithoutNewFields() throws {
        let legacyRef = Data(#"{"id":"\#(UUID().uuidString)","displayName":"roses"}"#.utf8)
        let ref = try JSONDecoder().decode(ImageRef.self, from: legacyRef)
        XCTAssertEqual(ref.fileName, "")
        XCTAssertEqual(ref.filterName, "")

        let legacySticker = Data(
            #"{"id":"\#(UUID().uuidString)","prompt":"cup","symbolName":"sparkles"}"#.utf8
        )
        let sticker = try JSONDecoder().decode(GeneratedSticker.self, from: legacySticker)
        XCTAssertEqual(sticker.fileName, "")
    }

    func testNewFieldsSurviveRoundTrip() throws {
        let ref = ImageRef(displayName: "roses", fileName: "a.png", filterName: "bw", frameName: "polaroid")
        let decoded = try JSONDecoder().decode(ImageRef.self, from: JSONEncoder().encode(ref))
        XCTAssertEqual(decoded, ref)
    }
}
