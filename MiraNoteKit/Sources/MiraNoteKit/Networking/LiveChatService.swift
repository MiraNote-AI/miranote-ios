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
        let toolTrace: [TraceEntry]?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case reply
            case toolTrace = "tool_trace"
        }
    }

    /// One tool call the backend made during the turn. Every tool has its
    /// own args shape, so decoding is lenient -- only create_note's
    /// title/body matter to the app.
    private struct TraceEntry: Decodable {
        let name: String
        let args: DraftArgs?

        struct DraftArgs: Decodable {
            let title: String?
            let body: String?
        }

        enum CodingKeys: String, CodingKey {
            case name
            case args
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            args = try? container.decodeIfPresent(DraftArgs.self, forKey: .args)
        }
    }

    public func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        let url = baseURL.appendingPathComponent("chat")
        let response: Response = try await client.postJSON(
            to: url,
            body: Request(sessionID: sessionID, message: message, notes: notes)
        )
        let draft = (response.toolTrace ?? [])
            .first { $0.name == "create_note" }
            .flatMap { entry -> ChatPageDraft? in
                guard let title = entry.args?.title else { return nil }
                return ChatPageDraft(title: title, body: entry.args?.body ?? "")
            }
        return ChatReply(text: response.reply, sessionID: response.sessionID, pageDraft: draft)
    }
}
