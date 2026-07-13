import Foundation

/// Live `TextTransformService`: posts the user's text to the text-clean-expand
/// POC and returns the transformed string. Endpoint/field mapping per the
/// integration spec (T3 table): clean -> /clean -> `cleaned`,
/// expand -> /expand -> `expanded`, polish -> /polish -> `polished`,
/// shorten -> /shorten -> `shortened` (the POC's target defaults to 50%).
public struct LiveTextTransformService: TextTransformService {
    private let baseURL: URL
    private let client: HTTPClient

    public init(
        baseURL: URL = MiraNoteConfig.Backend.textBaseURL,
        client: HTTPClient = HTTPClient()
    ) {
        self.baseURL = baseURL
        self.client = client
    }

    private struct Request: Encodable { let text: String }

    public func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        let url = baseURL.appendingPathComponent(mode.endpointPath)
        let response: Response = try await client.postJSON(to: url, body: Request(text: text))
        guard let value = response.value(for: mode) else {
            throw BackendError.decoding
        }
        return value
    }

    /// The POC names the result field after the endpoint, so one decodable
    /// with optional fields covers all three modes.
    private struct Response: Decodable {
        let cleaned: String?
        let expanded: String?
        let polished: String?
        let shortened: String?

        func value(for mode: TextTransformMode) -> String? {
            switch mode {
            case .clean: return cleaned
            case .expand: return expanded
            case .polish: return polished
            case .shorten: return shortened
            }
        }
    }
}

private extension TextTransformMode {
    var endpointPath: String {
        switch self {
        case .clean: return "clean"
        case .expand: return "expand"
        case .polish: return "polish"
        case .shorten: return "shorten"
        }
    }
}
