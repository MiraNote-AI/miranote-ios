#if DEBUG
import Foundation
import MiraNoteKit

/// The mock text transforms, except that under `-AI-LIMIT-REACHED` a
/// writer without Plus gets the text service's 429 for a used-up free
/// allowance (api #95), read by the live client as a tester's phone would.
struct UITestLimitedText: TextTransformService {
    private let mock = MockTextTransformService()

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        guard await Self.limited else { return try await mock.transform(text, mode: mode) }
        let live = LiveTextTransformService(baseURL: Self.invalidURL, client: Self.quotaClient)
        return try await live.transform(text, mode: mode)
    }

    /// `-AI-LIMIT-REACHED` and no Plus yet.
    static var limited: Bool {
        get async {
            guard ProcessInfo.processInfo.arguments.contains("-AI-LIMIT-REACHED") else { return false }
            return !(await PlusStore.shared.isPlus)
        }
    }

    static let invalidURL = URL(string: "http://uitest.invalid")!

    /// A client every request of which the server answers with the quota 429.
    static var quotaClient: HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuotaAnswer.self]
        return HTTPClient(session: URLSession(configuration: configuration), betaToken: nil)
    }

    private final class QuotaAnswer: URLProtocol {
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let body = #"{"reason": "quota", "feature": "expand", "plan": "free", "limit": 10, "#
                + #""resets_at": "2026-12-01T00:00:00+00:00"}"#
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}

/// -UITEST: the accounts service's `/subscriptions/sync`, counting the
/// chains sent.
struct UITestSubscriptions: SubscriptionsAPI {
    @MainActor static var synced = 0

    func sync(signedTransaction: String, signedRenewalInfo: String) async throws {
        await MainActor.run { Self.synced += 1 }
    }
}
#endif
