#if DEBUG
import Foundation
import MiraNoteKit

/// `-AI_EDIT_FAIL <status>:<reason>`: an AI edit fails the way /stylize
/// does (miranote-api #103), e.g. `422:edit_refused` or `503:busy`. The
/// edit goes through the live client, so a UI test sees what a tester
/// would: the body is read by the app's own code, not handed over as an
/// error.
enum UITestStylizeFailure {
    /// The status and reason asked for at launch, if any.
    static var requested: (status: Int, reason: String)? {
        guard let value = UserDefaults.standard.string(forKey: "AI_EDIT_FAIL") else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let status = Int(parts[0]) else { return nil }
        return (status, parts[1])
    }

    /// The edit: the requested failure if there is one, else `fallback`'s.
    static func stylize(
        image: Data, instruction: String, otherwise fallback: ImageStudioService
    ) async throws -> Data {
        guard requested != nil else { return try await fallback.stylize(image: image, instruction: instruction) }
        return try await studio().stylize(image: image, instruction: instruction)
    }

    /// A live studio whose every request gets that failure.
    private static func studio() -> LiveImageStudioService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Answer.self]
        return LiveImageStudioService(
            baseURL: URL(string: "http://uitest.invalid")!,
            client: HTTPClient(session: URLSession(configuration: configuration), betaToken: nil)
        )
    }

    /// Answers with the requested status and /stylize's error body.
    private final class Answer: URLProtocol {
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let (status, reason) = UITestStylizeFailure.requested ?? (500, "provider_error")
            let body = #"{"status": "error", "reason": "\#(reason)", "message": "server words"}"#
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
#endif
