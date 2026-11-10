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
        // The intent, not the number: generation outlives URLSession's 60s
        // default, so the request must set a budget of its own. What that
        // budget is, and why it sits under Cloudflare's 125s edge timeout,
        // belongs to TimeoutBudgetTests -- pinning the value in two places
        // means the next change to it has to be made twice.
        XCTAssertGreaterThan(
            try XCTUnwrap(captured?.timeoutInterval), 60,
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

    private func stylizeError(status: Int, body: String) async -> Error? {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        do {
            _ = try await makeService().stylize(image: Data("img".utf8), instruction: "make it blue")
            return nil
        } catch {
            return error
        }
    }

    /// Every failure /stylize names (miranote-api #96) shows its message,
    /// whatever the status.
    func testStylizeShowsTheServersMessage() async {
        let cases: [(Int, String)] = [
            (400, "unreadable_image"), (413, "image_too_large"), (422, "edit_refused"),
            (500, "no_image"), (502, "provider_error"), (503, "busy"), (504, "edit_timeout"),
        ]
        for (status, reason) in cases {
            let message = "Message for \(reason)."
            let body = #"{"status": "error", "reason": "\#(reason)", "message": "\#(message)"}"#
            let error = await stylizeError(status: status, body: body)

            XCTAssertEqual(error as? ImageEditError, ImageEditError(status: status, reason: reason, message: message))
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, message, "\(status)")
        }
    }

    /// An older server, or Cloudflare's page in place of the body: the
    /// status-only text as before, and a 504 reads as a timeout.
    func testStylizeWithoutTheServersMessageKeepsTheStatusText() async {
        let cases: [(Int, String, BackendError)] = [
            (502, "<html>Bad gateway</html>", .server(status: 502, detail: "<html>Bad gateway</html>")),
            (400, #"{"detail": "prompt is required"}"#, .server(status: 400, detail: #"{"detail": "prompt is required"}"#)),
            (500, #"{"status": "error", "reason": "no_image", "message": ""}"#,
             .server(status: 500, detail: #"{"status": "error", "reason": "no_image", "message": ""}"#)),
            (504, "<html>Gateway timeout</html>", .timedOut),
        ]
        for (status, body, expected) in cases {
            let error = await stylizeError(status: status, body: body)

            XCTAssertEqual(error as? BackendError, expected, "\(status) \(body)")
        }
        let notRunning = await stylizeError(status: 502, body: "<html>Bad gateway</html>")
        XCTAssertEqual(
            (notRunning as? LocalizedError)?.errorDescription,
            BackendError.server(status: 502, detail: nil).errorDescription
        )
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
