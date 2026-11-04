import Foundation

/// A compose job's state, as `GET /collections/jobs/{id}` reports it.
public enum ComposeJobStatus: Equatable, Sendable {
    case running
    case ok(TriggerMemory)
    /// The group did not pass (`reason` e.g. too_few_selected); `message`
    /// is Chinese, shown as is.
    case rejected(reason: String, message: String)
    /// The job failed (`timeout`, `model_error`, `bad_request`).
    case failed(reason: String, message: String)
    /// Unknown or older than 15 minutes (404): submit again.
    case expired
}

public enum ComposeError: Error, Equatable, Sendable {
    /// No connection, or the request timed out.
    case unreachable
    /// 429: wait and ask again.
    case rateLimited
    /// 400: the meta or photos were refused; the backend's message.
    case badRequest(String)
    /// 401: the build's beta token is missing or wrong.
    case unauthorized
    /// Any other status, or a body that does not decode.
    case server(Int)
}

/// The photo-collections backend: submit a group, then poll its job.
public protocol ComposeClient: Sendable {
    /// The job id.
    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String
    func poll(_ jobId: String) async throws -> ComposeJobStatus
    /// Every job in one request; an id the backend does not return reads
    /// `.expired`.
    func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus]
}

/// `ComposeClient` over the app's `HTTPClient`, which adds the beta token.
/// Each request is short (the work runs in a background job), well under
/// the tunnel's 125 s limit.
public struct LiveComposeClient: ComposeClient {
    private let http: HTTPClient
    private let baseURL: URL
    static let submitTimeout: TimeInterval = 60
    static let pollTimeout: TimeInterval = 20

    public init(http: HTTPClient = HTTPClient(), baseURL: URL = MiraNoteConfig.Backend.collectionsBaseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    public func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        let boundary = "MiraNote-\(UUID().uuidString)"
        var body = Data()
        func line(_ text: String) { body.append(Data("\(text)\r\n".utf8)) }
        line("--\(boundary)")
        line(#"Content-Disposition: form-data; name="meta""#)
        line("Content-Type: application/json; charset=utf-8")
        line("")
        body.append(try meta.encoded())
        line("")
        for photo in photos {
            line("--\(boundary)")
            line(#"Content-Disposition: form-data; name="photos"; filename="\#(photo.id).jpg""#)
            line("Content-Type: image/jpeg")
            line("")
            body.append(photo.jpeg)
            line("")
        }
        line("--\(boundary)--")

        var request = URLRequest(url: baseURL.appendingPathComponent("collections/compose"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = Self.submitTimeout
        let data = try await send(request)
        struct Accepted: Decodable {
            let jobId: String
            enum CodingKeys: String, CodingKey { case jobId = "job_id" }
        }
        guard let accepted = try? JSONDecoder().decode(Accepted.self, from: data) else {
            throw ComposeError.server(202)
        }
        return accepted.jobId
    }

    public func poll(_ jobId: String) async throws -> ComposeJobStatus {
        var request = URLRequest(url: baseURL.appendingPathComponent("collections/jobs").appendingPathComponent(jobId))
        request.timeoutInterval = Self.pollTimeout
        let data: Data
        do {
            data = try await send(request)
        } catch ComposeError.server(404) {
            return .expired
        }
        return try Self.status(from: data)
    }

    public func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus] {
        guard !jobIds.isEmpty else { return [:] }
        var components = URLComponents(url: baseURL.appendingPathComponent("collections/jobs"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "ids", value: jobIds.joined(separator: ","))]
        guard let url = components?.url else { throw ComposeError.server(0) }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.pollTimeout
        let data = try await send(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = object["jobs"] as? [String: Any]
        else { throw ComposeError.server(200) }
        var result: [String: ComposeJobStatus] = [:]
        for id in jobIds {
            guard let entry = jobs[id], JSONSerialization.isValidJSONObject(entry),
                  let body = try? JSONSerialization.data(withJSONObject: entry)
            else {
                result[id] = .expired
                continue
            }
            result[id] = try Self.status(from: body)
        }
        return result
    }

    static func status(from data: Data) throws -> ComposeJobStatus {
        struct Body: Decodable {
            let status: String
            let reason: String?
            let message: String?
            let memory: TriggerMemory?
        }
        guard let body = try? TriggerMemory.decoder.decode(Body.self, from: data) else {
            throw ComposeError.server(200)
        }
        switch body.status {
        case "running": return .running
        case "ok":
            guard let memory = body.memory else { throw ComposeError.server(200) }
            return .ok(memory)
        case "rejected": return .rejected(reason: body.reason ?? "", message: body.message ?? "")
        case "expired": return .expired
        default: return .failed(reason: body.reason ?? body.status, message: body.message ?? "")
        }
    }

    /// The HTTP client's errors in this contract's terms.
    private func send(_ request: URLRequest) async throws -> Data {
        do {
            return try await http.send(request)
        } catch let error as BackendError {
            switch error {
            case .unreachable, .timedOut: throw ComposeError.unreachable
            case .decoding: throw ComposeError.server(200)
            case .server(let status, let detail):
                switch status {
                case 400: throw ComposeError.badRequest(Self.message(in: detail) ?? "")
                case 401: throw ComposeError.unauthorized
                case 429: throw ComposeError.rateLimited
                default: throw ComposeError.server(status)
                }
            }
        }
    }

    private static func message(in detail: String?) -> String? {
        guard let data = detail?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return detail }
        return object["message"] as? String ?? detail
    }
}
