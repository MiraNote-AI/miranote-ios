import Foundation

/// What the backend reports for one judge call (snake_case on the wire).
public struct RoundUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var costCny: Double
    public var model: String

    public init(promptTokens: Int, completionTokens: Int, costCny: Double, model: String) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costCny = costCny
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case costCny = "cost_cny"
        case model
    }
}

/// One judge call. No coordinates: only the reply text, usage and the
/// `where` lines that were sent.
public struct RoundLogEntry: Codable, Equatable, Sendable {
    public var at: Date
    /// `round1`, `round2` or `shorten`.
    public var kind: String
    public var themeId: String?
    /// The re-ask key: the same key means the same question.
    public var key: String
    public var reply: String
    public var usage: RoundUsage
    public var problem: RoundOneProblem?
    public var `where`: [String: String]

    public init(at: Date, kind: String, themeId: String?, key: String, reply: String, usage: RoundUsage,
                problem: RoundOneProblem?, where: [String: String]) {
        self.at = at
        self.kind = kind
        self.themeId = themeId
        self.key = key
        self.reply = reply
        self.usage = usage
        self.problem = problem
        self.where = `where`
    }
}

/// `themes/rounds.json`: an append-only list of judge calls, the last 500 kept.
/// A repeated question is answered from here instead of asking again.
public struct RoundLog: Sendable {
    static let maxEntries = 500
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("rounds.json")
    }

    public func load() -> [RoundLogEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        if let data = try? Data(contentsOf: file),
           let stored = try? Self.decoder.decode(LenientFile.self, from: data) {
            return stored.entries.compactMap(\.value)
        }
        PhotoTriggerPaths.setAside(file)
        return []
    }

    public func append(_ entry: RoundLogEntry) throws {
        let kept = Array((load() + [entry]).suffix(Self.maxEntries))
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(entries: kept)).write(to: file, options: .atomic)
    }

    /// The last entry for `key` that was a usable answer: no problem, a reply.
    public func answer(for key: String) -> RoundLogEntry? {
        load().last { $0.key == key && $0.problem == nil && !$0.reply.isEmpty }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct File: Encodable {
        let version = 1
        let entries: [RoundLogEntry]
    }

    private struct LenientFile: Decodable {
        let entries: [Lenient<RoundLogEntry>]
    }
}
