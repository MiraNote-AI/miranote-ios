import Foundation

/// Errors surfaced by the live backend services. The `LocalizedError` text is
/// what the view models put into `lastError` for the user to see (spec D9 --
/// failures are visible, never silently faked).
public enum BackendError: Error, Equatable {
    /// Transport failure: server down, DNS, timeout, no network.
    case unreachable
    /// Server returned a non-2xx status. `detail` is the response body, if any.
    case server(status: Int, detail: String?)
    /// Response body could not be decoded into the expected shape.
    case decoding
}

extension BackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Couldn't reach the server. Make sure the backend is running."
        case .server(let status, _):
            return "The server returned an error (status \(status))."
        case .decoding:
            return "The server sent an unexpected response."
        }
    }
}

/// A minimal async HTTP client over `URLSession`. The session is injected so
/// tests can supply a stubbed `URLProtocol`. Transport failures and non-2xx
/// responses are mapped to typed `BackendError`s.
public struct HTTPClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Send a prepared request; return the body data on a 2xx response.
    public func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
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
