import Foundation

/// Live `ChatService`: posts to the chatbot POC `/chat` endpoint and carries
/// the server-issued session id forward so the conversation stays multi-turn.
/// Backend contract (main.py): request {session_id?, message} ->
/// {session_id, reply, tool_trace}.
public struct LiveChatService: ChatService {
    /// Deliberately above `MiraCanvasCoordinator.defaultTurnTimeout`.
    /// Without an explicit value this inherits URLSession's 60s default,
    /// which ties the turn clock and surfaces one stall under two
    /// different failure messages.
    public static let requestTimeout: TimeInterval = 75

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
        // Present only on canvas turns; the backend reads it as the
        // signal to release its page-edit tools.
        let page: PageBody?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case message
            case notes
            case page
        }
    }

    /// The map plus the base64 JPEG, in the shape the backend's PageIn
    /// expects.
    private struct PageBody: Encodable {
        let width: Double
        let height: Double
        let background: String
        let palette: [String]
        let elements: [PageMap.Element]
        let omitted: Int
        let image: String?

        init(_ context: PageContext) {
            width = context.map.width
            height = context.map.height
            background = context.map.background
            palette = context.map.palette
            elements = context.map.elements
            omitted = context.map.omitted
            image = context.image?.base64EncodedString()
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
        let args: Args?

        struct Args: Decodable {
            let title: String?
            let body: String?
            let prompt: String?
            let changes: [ElementChange]?
        }

        enum CodingKeys: String, CodingKey {
            case name
            case args
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            args = try? container.decodeIfPresent(Args.self, forKey: .args)
        }
    }

    public func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        let url = baseURL.appendingPathComponent("chat")
        let response: Response = try await client.postJSON(
            to: url,
            body: Request(
                sessionID: sessionID, message: message, notes: notes,
                page: page.map(PageBody.init)
            ),
            timeout: Self.requestTimeout
        )
        // A blank bubble is worse than a failure card: treat it as one.
        guard !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.decoding
        }
        let trace = response.toolTrace ?? []
        let draft = trace
            .first { $0.name == "create_note" }
            .flatMap { entry -> ChatPageDraft? in
                guard let title = entry.args?.title else { return nil }
                return ChatPageDraft(title: title, body: entry.args?.body ?? "")
            }
        // Several edit_page calls in one turn merge into one change, so
        // the user gets one receipt and one undo step.
        let edits = PageEditGuard.merge(
            trace.filter { $0.name == "edit_page" }.compactMap { $0.args?.changes }
        )
        let background = trace.compactMap { entry -> BackgroundRequest? in
            switch entry.name {
            case "set_background":
                guard let prompt = entry.args?.prompt, !prompt.isEmpty else { return nil }
                return .set(prompt: prompt)
            case "clear_background":
                return .clear
            default:
                return nil
            }
        }.last
        return ChatReply(
            text: response.reply, sessionID: response.sessionID, pageDraft: draft,
            pageEdits: edits, backgroundRequest: background
        )
    }
}
