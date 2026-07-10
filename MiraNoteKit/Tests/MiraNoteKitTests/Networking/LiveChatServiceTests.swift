import XCTest
@testable import MiraNoteKit

final class LiveChatServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service() -> LiveChatService {
        LiveChatService(
            baseURL: URL(string: "http://localhost:8003")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
    }

    private func sentBody(_ request: URLRequest) -> [String: Any] {
        let object = try? JSONSerialization.jsonObject(with: request.capturedBody ?? Data())
        return object as? [String: Any] ?? [:]
    }

    func testPostsToChatWithMessageAndReturnsReplyAndSession() async throws {
        var path: String?
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            path = request.url?.path
            sent = self.sentBody(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"session_id":"s1","reply":"Hello.","tool_trace":[]}"#.utf8))
        }
        let result = try await service().reply(to: "hi", sessionID: nil)
        XCTAssertEqual(path, "/chat")
        XCTAssertEqual(sent["message"] as? String, "hi")
        XCTAssertEqual(result.text, "Hello.")
        XCTAssertEqual(result.sessionID, "s1")
    }

    func testSendsSessionIdOnAFollowUpTurn() async throws {
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            sent = self.sentBody(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"session_id":"s1","reply":"Again.","tool_trace":[]}"#.utf8))
        }
        _ = try await service().reply(to: "more", sessionID: "s1")
        XCTAssertEqual(sent["session_id"] as? String, "s1")
    }

    func testParsesCreateNoteDraftFromToolTrace() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"""
            {"session_id":"s1","reply":"Draft ready.","tool_trace":[
                {"name":"find_quote","args":{"max":3},"result_preview":"[]"},
                {"name":"create_note","args":{"title":"Noodle night","body":"Warm broth."},"result_preview":"{}"}
            ]}
            """#
            return (response, Data(json.utf8))
        }
        let result = try await service().reply(to: "note this down", sessionID: nil)
        XCTAssertEqual(result.pageDraft, ChatPageDraft(title: "Noodle night", body: "Warm broth."))
    }

    func testNoDraftWhenNoCreateNoteInTrace() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"session_id":"s1","reply":"Hi.","tool_trace":[]}"#.utf8))
        }
        let result = try await service().reply(to: "hi", sessionID: nil)
        XCTAssertNil(result.pageDraft)
    }

    func testEmptyReplyBecomesADecodingError() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"session_id":"s1","reply":"  ","tool_trace":[]}"#.utf8))
        }
        do {
            _ = try await service().reply(to: "hi", sessionID: nil)
            XCTFail("a blank bubble must not reach the UI")
        } catch let error as BackendError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }

    func testServerErrorPropagatesAsBackendError() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":"chat failed"}"#.utf8))
        }
        do {
            _ = try await service().reply(to: "hi", sessionID: nil)
            XCTFail("expected an error")
        } catch let error as BackendError {
            guard case .server(let status, _) = error else { return XCTFail("expected .server, got \(error)") }
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("expected BackendError, got \(error)")
        }
    }
}
