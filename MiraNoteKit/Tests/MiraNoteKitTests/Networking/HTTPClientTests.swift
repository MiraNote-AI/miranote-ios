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

    func testTimeoutMapsToTimedOut() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            let _: Echo = try await makeClient().postJSON(to: url, body: Echo(value: "x"))
            XCTFail("expected an error")
        } catch let error as BackendError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }
}

extension HTTPClientTests {
    private func makeAuthenticated(_ token: String?) -> HTTPClient {
        HTTPClient(session: StubURLProtocol.makeSession(), betaToken: token)
    }

    private func capturingHeaders(
        _ run: (HTTPClient) async throws -> Void,
        client: HTTPClient
    ) async rethrows -> [String: String] {
        var captured: [String: String] = [:]
        StubURLProtocol.handler = { request in
            captured = request.allHTTPHeaderFields ?? [:]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        try await run(client)
        return captured
    }

    func testSendAttachesTheBearerToken() async throws {
        let headers = try await capturingHeaders({ client in
            _ = try await client.send(URLRequest(url: self.betaURL))
        }, client: makeAuthenticated("secret-token"))

        XCTAssertEqual(headers["Authorization"], "Bearer secret-token")
    }

    /// ImageStudio and LiveVoiceTranscriptionService build their own multipart
    /// requests and hand them to `send`, so injecting there is what makes every
    /// call site authenticated rather than the JSON path only.
    func testAnAlreadyBuiltRequestIsAuthenticatedToo() async throws {
        var request = URLRequest(url: betaURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=x", forHTTPHeaderField: "Content-Type")

        let headers = try await capturingHeaders({ client in
            _ = try await client.send(request)
        }, client: makeAuthenticated("secret-token"))

        XCTAssertEqual(headers["Authorization"], "Bearer secret-token")
        XCTAssertEqual(headers["Content-Type"], "multipart/form-data; boundary=x")
    }

    func testPostJSONIsAuthenticatedToo() async throws {
        struct Body: Codable { let value: String }
        let headers = try await capturingHeaders({ client in
            let _: [String: String] = try await client.postJSON(to: self.betaURL, body: Body(value: "x"))
        }, client: makeAuthenticated("secret-token"))

        XCTAssertEqual(headers["Authorization"], "Bearer secret-token")
    }

    /// A build with no token compiles and runs; it just gets 401s it can
    /// explain, rather than crashing or sending "Bearer nil".
    func testNoTokenMeansNoHeader() async throws {
        let headers = try await capturingHeaders({ client in
            _ = try await client.send(URLRequest(url: self.betaURL))
        }, client: makeAuthenticated(nil))

        XCTAssertNil(headers["Authorization"])
    }

    private var betaURL: URL { URL(string: "https://beta-text.miranote.app/polish")! }
}
