import Foundation

/// Live `MoodService`: posts the page's words to the text-clean-expand POC's
/// `/mood` and returns one of the six moods. A label this build does not
/// know reads as neutral -- a mood is decoration, never an error.
public struct LiveMoodService: MoodService {
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
    private struct Response: Decodable { let mood: String }

    public func mood(for text: String) async throws -> Mood {
        let url = baseURL.appendingPathComponent("mood")
        let response: Response = try await client.postJSON(to: url, body: Request(text: text))
        return Mood(rawValue: response.mood) ?? .neutral
    }
}
