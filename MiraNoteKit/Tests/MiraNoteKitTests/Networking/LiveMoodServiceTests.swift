import XCTest
@testable import MiraNoteKit

final class LiveMoodServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service() -> LiveMoodService {
        LiveMoodService(
            baseURL: URL(string: "http://localhost:8001")!,
            client: HTTPClient(session: StubURLProtocol.makeSession())
        )
    }

    private func respond(_ body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    func testPostsTheTextToMoodAndReturnsTheMood() async throws {
        var path: String?
        var text: String?
        StubURLProtocol.handler = { request in
            path = request.url?.path
            let object = try? JSONSerialization.jsonObject(with: request.capturedBody ?? Data()) as? [String: Any]
            text = object?["text"] as? String
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"mood":"tender"}"#.utf8))
        }
        let mood = try await service().mood(for: "missing home")
        XCTAssertEqual(path, "/mood")
        XCTAssertEqual(text, "missing home")
        XCTAssertEqual(mood, .tender)
    }

    func testAMoodThisBuildDoesNotKnowIsNeutral() async throws {
        respond(#"{"mood":"ecstatic"}"#)
        let mood = try await service().mood(for: "a page")
        XCTAssertEqual(mood, .neutral)
    }

    func testServerErrorPropagates() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await service().mood(for: "a page")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BackendError, .server(status: 404, detail: nil))
        }
    }
}
