import XCTest
@testable import MiraNoteKit

final class LiveVoiceTranscriptionServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service(language: String = "en") -> LiveVoiceTranscriptionService {
        LiveVoiceTranscriptionService(
            baseURL: URL(string: "http://localhost:8005")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            language: language
        )
    }

    func testUploadsMultipartToTranscribeWithExpectedQuery() async throws {
        var url: URL?
        var contentType: String?
        var bodyString: String?
        StubURLProtocol.handler = { request in
            url = request.url
            contentType = request.value(forHTTPHeaderField: "Content-Type")
            bodyString = request.capturedBody.flatMap { String(data: $0, encoding: .ascii) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"raw_text":"hello","corrected_text":"Hello."}"#.utf8))
        }

        _ = try await service().transcribe(audio: Data("AUDIODATA".utf8), filename: "recording.m4a")

        let components = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.path, "/transcribe")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["correct"], "true")
        XCTAssertEqual(query["with_emotion"], "false")
        XCTAssertEqual(query["lang"], "en")

        XCTAssertTrue(contentType?.contains("multipart/form-data; boundary=") ?? false)
        let body = try XCTUnwrap(bodyString)
        XCTAssertTrue(
            body.contains(#"name="file"; filename="recording.m4a""#),
            "multipart must carry the file field + filename"
        )
        XCTAssertTrue(body.contains("AUDIODATA"), "multipart must carry the audio bytes")
    }

    func testReturnsCorrectedTextWhenPresent() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"raw_text":"helo","corrected_text":"Hello."}"#.utf8))
        }
        let result = try await service().transcribe(audio: Data("x".utf8), filename: "r.m4a")
        XCTAssertEqual(result, "Hello.")
    }

    func testFallsBackToRawTextWhenCorrectionIsNull() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"raw_text":"raw only","corrected_text":null}"#.utf8))
        }
        let result = try await service().transcribe(audio: Data("x".utf8), filename: "r.m4a")
        XCTAssertEqual(result, "raw only")
    }

    func testServerErrorPropagatesAsBackendError() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":"Audio too small"}"#.utf8))
        }
        do {
            _ = try await service().transcribe(audio: Data("x".utf8), filename: "r.m4a")
            XCTFail("expected an error")
        } catch let error as BackendError {
            guard case .server(let status, _) = error else { return XCTFail("expected .server, got \(error)") }
            XCTAssertEqual(status, 422)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }
}
