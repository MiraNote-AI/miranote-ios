import Foundation

/// Errors surfaced by the live backend services. The `LocalizedError` text is
/// what the view models put into `lastError` for the user to see (spec D9 --
/// failures are visible, never silently faked).
public enum BackendError: Error, Equatable {
    /// Transport failure: server down, DNS, no network.
    case unreachable
    /// The server accepted the connection but never answered in time.
    case timedOut
    /// The request went out, but its answer was lost: the connection
    /// dropped, or what came back could not be read. The server may have
    /// acted on it.
    case answerLost
    /// Server returned a non-2xx status. `detail` is the response body, if any.
    case server(status: Int, detail: String?)
    /// Response body could not be decoded into the expected shape.
    case decoding
    /// A 429 with `reason: quota` (api #95 step 3): the signed-in writer
    /// used up this feature's allowance for its window.
    case limitReached(AILimit)
}

/// Which allowance ran out, from the AI service's 429 body
/// `{"reason": "quota", "feature", "plan", ...}`.
public struct AILimit: Equatable, Sendable {
    /// `chat`, `expand`, `image_generate`, `image_edit`, `photo_push`, `mood`.
    public let feature: String
    /// `free` or `plus`: only a free writer is offered Plus.
    public let plan: String

    public init(feature: String, plan: String) {
        self.feature = feature
        self.plan = plan
    }

    public var isFree: Bool { plan != "plus" }

    /// The limit in a 429 body, nil for any other 429 (the beta token's
    /// rate limit has no `reason`).
    init?(body: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["reason"] as? String == "quota" else { return nil }
        self.init(feature: object["feature"] as? String ?? "", plan: object["plan"] as? String ?? "free")
    }
}

extension BackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreachable, .answerLost:
            return String(appCopy: """
                Couldn't reach MiraNote's AI server. Check your connection -- \
                if that is fine, the server is offline and the team needs to know.
                """)
        case .timedOut:
            return String(appCopy: """
                That took longer than the server allows. Try again once; \
                if it fails a second time, tell the team rather than retrying.
                """)
        case .server(let status, let detail):
            return Self.guardMessage(status: status, detail: detail) ?? Self.message(for: status)
        case .decoding:
            return String(appCopy: "The server sent an unexpected response.")
        case .limitReached(let limit):
            return limit.isFree
                ? String(appCopy: "You've reached the free limit for this. MiraNote Plus gives you more.")
                : String(appCopy: "You've reached this limit for now. Try again later.")
        }
    }

    /// A 503 from the AI services' account guard says why in its `reason`
    /// (miranote-api #112, #118): the accounts service did not answer, or
    /// the feature's daily cost budget is used up until `resets_at`, shown
    /// in the phone's time. nil for any other answer: a 503 without one is
    /// the image provider's, as before.
    static func guardMessage(status: Int, detail: String?, timeZone: TimeZone = .current) -> String? {
        guard status == 503, let data = detail?.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch body["reason"] as? String {
        case "accounts_unavailable":
            return String(appCopy: "MiraNote's sign-in service isn't answering right now. Try again shortly.")
        case "service_paused":
            guard let back = (body["resets_at"] as? String).flatMap(isoDate) else {
                return String(appCopy: "Mira has paused this for now. Try again later.")
            }
            let style = Date.FormatStyle(date: .omitted, time: .shortened,
                                         locale: AppSettings.shared.language.locale, timeZone: timeZone)
            return String(appCopy: "Mira has paused this for now. Try again after \(back.formatted(style)).")
        default:
            return nil
        }
    }

    /// A time as Python's `isoformat()` writes it, with or without
    /// fractional seconds.
    private static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
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
            return String(appCopy: """
                This build cannot get into the beta -- its access was never set \
                up, or has since been replaced. Ask the team for an updated \
                build; reinstalling this one will not help.
                """)
        case 429:
            return String(appCopy: """
                You are sending requests faster than the beta allows. \
                Wait about a minute and it clears on its own.
                """)
        case 502:
            return String(appCopy: """
                MiraNote's AI server is not running. It lives on a Mac someone \
                has to start -- let the team know.
                """)
        case 503:
            return String(appCopy: """
                The image service has used up its quota with the provider. \
                Nothing on your phone can fix this one; try again later.
                """)
        case 504:
            // A service gave up on a request that ran past its own time
            // budget. Unlike .timedOut nothing is wrong with the connection,
            // so a retry is the whole fix. Generic on purpose: this table
            // serves every endpoint, and /generate says "picture" itself
            // (GenerationTimeoutError).
            return String(appCopy: """
                The server took too long to answer. Try again; \
                if it keeps happening, tell the team.
                """)
        case 530:
            return String(appCopy: """
                The link to MiraNote's AI server is down, most likely because \
                its Mac is asleep or off the network. Let the team know.
                """)
        default:
            return String(appCopy: "The server returned an error (status \(status)).")
        }
    }
}

/// A minimal async HTTP client over `URLSession`. The session is injected so
/// tests can supply a stubbed `URLProtocol`. Transport failures and non-2xx
/// responses are mapped to typed `BackendError`s.
public struct HTTPClient: Sendable {
    private let session: URLSession
    private let betaToken: String?
    private let userTokens: UserTokenSource?

    /// `userTokens`: signed in, requests carry our access token instead of
    /// the beta token (api #95 step 3). The accounts service's own calls
    /// pass nil: a refresh must never wait on a refresh.
    public init(
        session: URLSession = .shared,
        betaToken: String? = MiraNoteConfig.Backend.betaToken,
        userTokens: UserTokenSource? = UserTokens.current
    ) {
        self.session = session
        self.betaToken = betaToken
        self.userTokens = userTokens
    }

    /// Send a prepared request; return the body data on a 2xx response.
    ///
    /// The bearer token is attached here rather than at each call site. This
    /// is the one funnel every request passes through, including the two that
    /// are built as multipart elsewhere, so injecting here is what makes
    /// "every call is authenticated" true rather than "every call we
    /// remembered".
    ///
    /// Signed in, the bearer is our access token and the request gets an
    /// `X-Request-ID`, which the AI services meter by. A 401 renews the
    /// token once (one refresh for all requests that got it) and sends the
    /// request again with the same id: the 401 came before anything was
    /// counted. Signed out, or in a build that offers no sign-in, the beta
    /// token goes as before.
    public func send(_ request: URLRequest) async throws -> Data {
        var request = request
        guard let userTokens, let token = try await userTokens.accessTokenIfSignedIn() else {
            if let betaToken {
                request.setValue("Bearer \(betaToken)", forHTTPHeaderField: "Authorization")
            }
            return try checked(await exchange(request))
        }
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await exchange(request)
        guard response.statusCode == 401 else { return try checked((data, response)) }
        let renewed = try await userTokens.renewAccessToken(after: token)
        request.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
        return try checked(await exchange(request))
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            switch (error as? URLError)?.code {
            case .timedOut: throw BackendError.timedOut
            case .networkConnectionLost, .badServerResponse, .cannotParseResponse,
                 .cannotDecodeContentData, .cannotDecodeRawData:
                throw BackendError.answerLost
            default: throw BackendError.unreachable
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.unreachable
        }
        return (data, http)
    }

    private func checked(_ answer: (Data, HTTPURLResponse)) throws -> Data {
        let (data, http) = answer
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429, let limit = AILimit(body: data) {
                throw BackendError.limitReached(limit)
            }
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
