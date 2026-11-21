#if DEBUG
import Foundation
import MiraNoteKit

/// The mock text transforms, except that under `-AI-LIMIT-REACHED` a
/// writer without Plus gets the text service's 429 for a used-up free
/// allowance (api #95), read by the live client as a tester's phone would.
struct UITestLimitedText: TextTransformService {
    private let mock = MockTextTransformService()

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        guard let live = await limitedLive() else { return try await mock.transform(text, mode: mode) }
        return try await live.transform(text, mode: mode)
    }

    func rewrite(_ text: String, instruction: String) async throws -> String {
        guard let live = await limitedLive() else { return try await mock.rewrite(text, instruction: instruction) }
        return try await live.rewrite(text, instruction: instruction)
    }

    /// The live client answered by the quota 429, while the limit applies.
    private func limitedLive() async -> LiveTextTransformService? {
        let limited = ProcessInfo.processInfo.arguments.contains("-AI-LIMIT-REACHED")
        guard limited, !(await PlusStore.shared.isPlus) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuotaAnswer.self]
        return LiveTextTransformService(
            baseURL: URL(string: "http://uitest.invalid")!,
            client: HTTPClient(session: URLSession(configuration: configuration), betaToken: nil)
        )
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
