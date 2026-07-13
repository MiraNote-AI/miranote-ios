import XCTest
@testable import MiraNoteKit

final class LiveTextTransformServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service() -> LiveTextTransformService {
        LiveTextTransformService(
            baseURL: URL(string: "http://localhost:8001")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
    }

    private func sentText(_ request: URLRequest) -> String? {
        let object = try? JSONSerialization.jsonObject(with: request.capturedBody ?? Data()) as? [String: Any]
        return object?["text"] as? String
    }

    func testCleanPostsToCleanWithBodyAndReturnsCleanedField() async throws {
        var path: String?
        var text: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            text = self.sentText(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"original":"hi","cleaned":"Hi."}"#.utf8))
        }
        let result = try await service().transform("hi", mode: .clean)
        XCTAssertEqual(path, "/clean")
        XCTAssertEqual(text, "hi")
        XCTAssertEqual(result, "Hi.")
    }

    func testExpandPostsToExpandAndReturnsExpandedField() async throws {
        var path: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"original":"a","expanded":"a and more"}"#.utf8))
        }
        let result = try await service().transform("a", mode: .expand)
        XCTAssertEqual(path, "/expand")
        XCTAssertEqual(result, "a and more")
    }

    func testPolishPostsToPolishAndReturnsPolishedField() async throws {
        var path: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"original":"a","polished":"A."}"#.utf8))
        }
        let result = try await service().transform("a", mode: .polish)
        XCTAssertEqual(path, "/polish")
        XCTAssertEqual(result, "A.")
    }

    func testShortenPostsToShortenAndReturnsShortenedField() async throws {
        var path: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"original":"a long note","shortened":"a note","target":"50%"}"#.utf8))
        }
        let result = try await service().transform("a long note", mode: .shorten)
        XCTAssertEqual(path, "/shorten")
        XCTAssertEqual(result, "a note")
    }

    func testServerErrorPropagatesAsBackendError() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":"LLM call failed"}"#.utf8))
        }
        do {
            _ = try await service().transform("a", mode: .clean)
            XCTFail("expected an error")
        } catch let error as BackendError {
            guard case .server(let status, _) = error else { return XCTFail("expected .server, got \(error)") }
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }
}
