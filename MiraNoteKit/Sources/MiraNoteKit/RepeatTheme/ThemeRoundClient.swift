import Foundation

/// What the backend sends back for one judge call: Qwen's reply text as it
/// is (the phone parses and checks it), the "where" line the backend made
/// of each offered group (round 1 only), and the call's usage.
public struct RoundReply: Equatable, Sendable {
    public var reply: String
    /// Group id -> its "where it is concentrated" line; empty outside round 1.
    public var `where`: [String: String]
    public var usage: RoundUsage

    public init(reply: String, where: [String: String], usage: RoundUsage) {
        self.reply = reply
        self.where = `where`
        self.usage = usage
    }
}

public enum ThemeRoundError: Error, Equatable, Sendable {
    /// No connection, or the request timed out.
    case unreachable
    /// 401: the build's beta token is missing or wrong.
    case unauthorized
    /// 429.
    case rateLimited
    /// 400: the meta or images were refused.
    case badRequest
    /// 502: the model timed out or failed (`reason` `timeout` / `model_error`).
    case model(reason: String, usage: RoundUsage)
    /// Any other status, or a body that does not decode.
    case server(Int)
}

/// The meta of the backend's round-2 call (`POST /collections/rounds/2`):
/// the theme and the numbered candidates, with the two compare lists.
public struct RoundTwoRequest: Encodable, Equatable, Sendable {
    public struct Theme: Encodable, Equatable, Sendable {
        public let name: String
        /// May be empty (a pile has none).
        public let noun: String
        /// May be empty.
        public let samePart: String

        public init(name: String, noun: String, samePart: String) {
            self.name = name
            self.noun = noun
            self.samePart = samePart
        }

        private enum CodingKeys: String, CodingKey {
            case name, noun
            case samePart = "same_part"
        }
    }

    public struct Photo: Encodable, Equatable, Sendable {
        // swiftlint:disable:next identifier_name
        public let n: Int

        // swiftlint:disable:next identifier_name
        public init(n: Int) {
            self.n = n
        }
    }

    /// The backend takes at most this many names in each list.
    static let maxPushed = 20
    static let maxBlocked = 50

    public let theme: Theme
    public let photos: [Photo]
    /// Repeat theme names pushed in the last 60 days.
    public let pushed: [String]
    /// Names of the themes the user blocked.
    public let blocked: [String]

    /// `pushed` and `blocked` are cut to the backend's limits.
    public init(theme: Theme, photos: [Photo], pushed: [String], blocked: [String]) {
        self.theme = theme
        self.photos = photos
        self.pushed = Array(pushed.prefix(Self.maxPushed))
        self.blocked = Array(blocked.prefix(Self.maxBlocked))
    }
}

/// The repeat-theme judge rounds; Qwen's key stays on the backend.
public protocol ThemeRoundClient: Sendable {
    /// Images are numbered as in `request.photos` (`n.jpg`), 336 px, bare.
    func roundOne(_ request: RoundOneRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply
    func roundTwo(_ request: RoundTwoRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply
    /// At most 7 items (the backend's limit).
    func shorten(_ items: [ShortenItem]) async throws -> RoundReply
}

/// `ThemeRoundClient` over the app's `HTTPClient`, which adds the beta (or
/// signed-in) token. The backend gives the model 45 s; a request waits 60 s,
/// under the tunnel's 125 s.
public struct LiveThemeRoundClient: ThemeRoundClient {
    private let http: HTTPClient
    private let baseURL: URL
    static let timeout: TimeInterval = 60

    public init(baseURL: URL = MiraNoteConfig.Backend.collectionsBaseURL, http: HTTPClient = HTTPClient()) {
        self.http = http
        self.baseURL = baseURL
    }

    public func roundOne(_ request: RoundOneRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        try await multipart("collections/rounds/1", meta: Self.encoder.encode(request), images: images)
    }

    public func roundTwo(_ request: RoundTwoRequest, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        try await multipart("collections/rounds/2", meta: Self.encoder.encode(request), images: images)
    }

    /// Sorted keys: the same meta is always the same bytes.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public func shorten(_ items: [ShortenItem]) async throws -> RoundReply {
        struct Items: Encodable {
            let items: [ShortenItem]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("collections/rounds/shorten"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(Items(items: items))
        request.timeoutInterval = Self.timeout
        return try await send(request)
    }

    /// `meta` plus one `photos` part per image, named `n.jpg`.
    private func multipart(_ path: String, meta: Data, images: [(n: Int, jpeg: Data)]) async throws -> RoundReply {
        let boundary = "MiraNote-\(UUID().uuidString)"
        var body = Data()
        func line(_ text: String) { body.append(Data("\(text)\r\n".utf8)) }
        line("--\(boundary)")
        line(#"Content-Disposition: form-data; name="meta""#)
        line("Content-Type: application/json; charset=utf-8")
        line("")
        body.append(meta)
        line("")
        for image in images {
            line("--\(boundary)")
            line(#"Content-Disposition: form-data; name="photos"; filename="\#(image.n).jpg""#)
            line("Content-Type: image/jpeg")
            line("")
            body.append(image.jpeg)
            line("")
        }
        line("--\(boundary)--")

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = Self.timeout
        return try await send(request)
    }

    private struct Body: Decodable {
        let reply: String?
        let `where`: [String: String]?
        let usage: RoundUsage?
        let reason: String?
    }

    private func send(_ request: URLRequest) async throws -> RoundReply {
        let data: Data
        do {
            data = try await http.send(request)
        } catch let error as BackendError {
            throw Self.roundError(error)
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), let reply = body.reply,
              let usage = body.usage else { throw ThemeRoundError.server(200) }
        return RoundReply(reply: reply, where: body.where ?? [:], usage: usage)
    }

    private static func roundError(_ error: BackendError) -> ThemeRoundError {
        switch error {
        case .unreachable, .timedOut, .answerLost: return .unreachable
        case .decoding: return .server(200)
        case .limitReached: return .rateLimited
        case .server(let status, let detail):
            switch status {
            case 400: return .badRequest
            case 401: return .unauthorized
            case 429: return .rateLimited
            case 502:
                guard let data = detail?.data(using: .utf8),
                      let body = try? JSONDecoder().decode(Body.self, from: data), let usage = body.usage
                else { return .server(502) }
                return .model(reason: body.reason ?? "", usage: usage)
            default: return .server(status)
            }
        }
    }
}
