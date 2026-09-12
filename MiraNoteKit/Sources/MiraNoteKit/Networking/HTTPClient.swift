import Foundation

/// Errors surfaced by the live backend services. The `LocalizedError` text is
/// what the view models put into `lastError` for the user to see (spec D9 --
/// failures are visible, never silently faked).
public enum BackendError: Error, Equatable {
    /// Transport failure: server down, DNS, no network.
    case unreachable
    /// The server accepted the connection but never answered in time.
    case timedOut
    /// Server returned a non-2xx status. `detail` is the response body, if any.
    case server(status: Int, detail: String?)
    /// Response body could not be decoded into the expected shape.
    case decoding
}

extension BackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return """
                Couldn't reach MiraNote's AI server. Check your connection -- \
                if that is fine, the server is offline and the team needs to know.
                """
        case .timedOut:
            return """
                That took longer than the server allows. Try again once; \
                if it fails a second time, tell the team rather than retrying.
                """
        case .server(let status, _):
            return Self.message(for: status)
        case .decoding:
            return "The server sent an unexpected response."
        }
    }

    /// Statuses this deployment can actually produce, each paired with the one
    /// action that resolves it.
    ///
    /// The raw code is deliberately absent from these: a tester who reads
    /// "status 429" reports "the app is broken", which is the triage problem
    /// this mapping exists to remove. Anything unmapped still shows its code,
    /// because an unexpected status is a developer's problem and the number is
    /// the useful part.
    private static func message(for status: Int) -> String {
        switch status {
        case 401:
            // Covers both cases, because the first one to actually happen was
            // the one the earlier wording denied: a TestFlight build that was
            // never given a token at all, not one whose token was rotated.
            return """
                This build cannot get into the beta -- its access was never set \
                up, or has since been replaced. Ask the team for an updated \
                build; reinstalling this one will not help.
                """
        case 429:
            return """
                You are sending requests faster than the beta allows. \
                Wait about a minute and it clears on its own.
                """
        case 502:
            return """
                MiraNote's AI server is not running. It lives on a Mac someone \
                has to start -- let the team know.
                """
        case 503:
            return """
                The image service has used up its quota with the provider. \
                Nothing on your phone can fix this one; try again later.
                """
        case 530:
            return """
                The link to MiraNote's AI server is down, most likely because \
                its Mac is asleep or off the network. Let the team know.
                """
        default:
            return "The server returned an error (status \(status))."
        }
    }
}

/// A minimal async HTTP client over `URLSession`. The session is injected so
/// tests can supply a stubbed `URLProtocol`. Transport failures and non-2xx
/// responses are mapped to typed `BackendError`s.
public struct HTTPClient: Sendable {
    private let session: URLSession
    private let betaToken: String?

    public init(
        session: URLSession = .shared,
        betaToken: String? = MiraNoteConfig.Backend.betaToken
    ) {
        self.session = session
        self.betaToken = betaToken
    }

    /// Send a prepared request; return the body data on a 2xx response.
    ///
    /// The bearer token is attached here rather than at each call site. This
    /// is the one funnel every request passes through, including the two that
    /// are built as multipart elsewhere, so injecting here is what makes
    /// "every call is authenticated" true rather than "every call we
    /// remembered".
    public func send(_ request: URLRequest) async throws -> Data {
        var request = request
        if let betaToken {
            request.setValue("Bearer \(betaToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw BackendError.timedOut
            }
            throw BackendError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.unreachable
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = data.isEmpty ? nil : String(data: data, encoding: .utf8)
            throw BackendError.server(status: http.statusCode, detail: detail)
        }
        return data
    }

    /// POST `body` encoded as JSON, then decode the response body.
    /// `timeout` overrides URLSession's 60s default for endpoints that
    /// legitimately work longer (image generation).
    public func postJSON<Body: Encodable, Response: Decodable>(
        to url: URL,
        body: Body,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        if let timeout {
            request.timeoutInterval = timeout
        }
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendError.decoding
        }
    }
}
