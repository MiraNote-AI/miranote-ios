import Foundation

/// Live `ChatService`: posts to the chatbot POC `/chat` endpoint and carries
/// the server-issued session id forward so the conversation stays multi-turn.
/// Backend contract (main.py): request {session_id?, message} ->
/// {session_id, reply, tool_trace}.
public struct LiveChatService: ChatService {
    private let baseURL: URL
    private let client: HTTPClient

    public init(
        baseURL: URL = MiraNoteConfig.Backend.chatBaseURL,
        client: HTTPClient = HTTPClient()
    ) {
        self.baseURL = baseURL
        self.client = client
    }

    private struct Request: Encodable {
        let sessionID: String?
        let message: String
        // Always present: the app's conversations are journal mode.
        let notes: [ChatNote]

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case message
            case notes
        }
    }

    private struct Response: Decodable {
        let sessionID: String
        let reply: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case reply
        }
    }

    public func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        let url = baseURL.appendingPathComponent("chat")
        let response: Response = try await client.postJSON(
            to: url,
            body: Request(sessionID: sessionID, message: message, notes: notes)
        )
        return ChatReply(text: response.reply, sessionID: response.sessionID)
    }
}
