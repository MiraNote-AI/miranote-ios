import XCTest
@testable import MiraNoteKit

final class HTTPClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient() -> HTTPClient {
        HTTPClient(session: StubURLProtocol.makeSession())
    }

    private struct Echo: Codable, Equatable { let value: String }

    private let url = URL(string: "http://localhost:8001/clean")!

    func testPostJSONDecodesA200Response() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(Echo(value: "hi")))
        }
        let result: Echo = try await makeClient().postJSON(to: url, body: Echo(value: "x"))
        XCTAssertEqual(result, Echo(value: "hi"))
    }

    func testPostJSONSendsTheEncodedBody() async throws {
        var captured: Data?
        StubURLProtocol.handler = { request in
            captured = request.capturedBody
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(Echo(value: "ok")))
        }
        let _: Echo = try await makeClient().postJSON(to: url, body: Echo(value: "sent"))
        let decoded = try JSONDecoder().decode(Echo.self, from: XCTUnwrap(captured))
        XCTAssertEqual(decoded, Echo(value: "sent"))
    }

    func testNon2xxMapsToServerError() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":"LLM call failed"}"#.utf8))
        }
        do {
            let _: Echo = try await makeClient().postJSON(to: url, body: Echo(value: "x"))
            XCTFail("expected an error")
        } catch let error as BackendError {
            guard case .server(let status, _) = error else { return XCTFail("expected .server, got \(error)") }
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }

    func testTransportFailureMapsToUnreachable() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            let _: Echo = try await makeClient().postJSON(to: url, body: Echo(value: "x"))
            XCTFail("expected an error")
        } catch let error as BackendError {
            XCTAssertEqual(error, .unreachable)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }
}
