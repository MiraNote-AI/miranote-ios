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

    // MARK: Canvas turns

    private var canvasMap: PageMap {
        PageMap.build(from: Memory(items: []), canvasWidth: 393).map
    }

    private func canned(_ json: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
    }

    func testCanvasTurnSendsThePageAndItsImage() async throws {
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            sent = self.sentBody(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"session_id":"s","reply":"ok","tool_trace":[]}"#.utf8))
        }
        _ = try await service().reply(
            to: "move the title up", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: Data([0xFF, 0xD8]))
        )
        let page = sent["page"] as? [String: Any]
        XCTAssertEqual(page?["width"] as? Double, 393)
        XCTAssertNotNil(page?["image"] as? String, "the JPEG rides along base64-encoded")
        XCTAssertNotNil(page?["palette"], "the model must be told which colors exist")
    }

    func testChatScreenTurnSendsNoPage() async throws {
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            sent = self.sentBody(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"session_id":"s","reply":"ok","tool_trace":[]}"#.utf8))
        }
        _ = try await service().reply(to: "hello", sessionID: nil, notes: [])
        XCTAssertNil(sent["page"])
    }

    func testEditPageCallsAreReadOutOfTheToolTrace() async throws {
        canned("""
        {"session_id":"s","reply":"Moved it up.","tool_trace":[
          {"name":"edit_page","args":{"changes":[
            {"id":"t1","x":28,"y":24,"size":34,"color":"forest","layer":"front"}]}}]}
        """)
        let reply = try await service().reply(
            to: "move it", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.pageEdits.count, 1)
        XCTAssertEqual(reply.pageEdits[0].handle, "t1")
        XCTAssertEqual(reply.pageEdits[0].pointSize, 34)
        XCTAssertEqual(reply.pageEdits[0].layer, .front)
    }

    func testSeveralEditPageCallsMergeWithTheLaterOneWinning() async throws {
        canned("""
        {"session_id":"s","reply":"ok","tool_trace":[
          {"name":"edit_page","args":{"changes":[{"id":"t1","x":10,"y":10}]}},
          {"name":"edit_page","args":{"changes":[{"id":"t1","x":99}]}}]}
        """)
        let reply = try await service().reply(
            to: "move it", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.pageEdits.count, 1, "one turn, one change")
        XCTAssertEqual(reply.pageEdits[0].x, 99)
        XCTAssertEqual(reply.pageEdits[0].y, 10)
    }

    func testBackgroundRequestsAreReadOutOfTheToolTrace() async throws {
        canned("""
        {"session_id":"s","reply":"Painting.","tool_trace":[
          {"name":"set_background","args":{"prompt":"a quiet dusk sky"}}]}
        """)
        let reply = try await service().reply(
            to: "change the background", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.backgroundRequest, .set(prompt: "a quiet dusk sky"))
    }

    func testClearBackgroundIsReadOutOfTheToolTrace() async throws {
        canned("""
        {"session_id":"s","reply":"Cleared.","tool_trace":[
          {"name":"clear_background","args":{}}]}
        """)
        let reply = try await service().reply(
            to: "remove the background", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.backgroundRequest, .clear)
    }

    func testUnknownToolCallsAreIgnored() async throws {
        canned("""
        {"session_id":"s","reply":"ok","tool_trace":[{"name":"look_at_page","args":{}}]}
        """)
        let reply = try await service().reply(
            to: "how does it look", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertTrue(reply.pageEdits.isEmpty)
        XCTAssertNil(reply.backgroundRequest)
    }

    func testTheRequestClockSitsAboveTheTurnClock() {
        // The ladder: look 25s < turn 60s < request 75s. If these ever
        // cross, one stall surfaces under two different messages and the
        // user cannot tell which happened.
        let turn = MiraCanvasCoordinator.defaultTurnTimeout
        XCTAssertGreaterThan(
            Duration.seconds(LiveChatService.requestTimeout), turn,
            "the HTTP clock must never beat the turn clock"
        )
    }
}
