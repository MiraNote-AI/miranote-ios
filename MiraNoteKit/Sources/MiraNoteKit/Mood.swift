import Foundation

/// A page's overall mood, judged once by the text service from its words
/// and photo descriptions. The star jar colors each page's star with it.
public enum Mood: String, Codable, CaseIterable, Sendable {
    case joyful, calm, tender, low, tense, neutral

    public var displayName: String { rawValue.capitalized }
}

/// Backend mapping: text-clean-expand POC, `POST /mood`.
public protocol MoodService: Sendable {
    func mood(for text: String) async throws -> Mood
}

/// Deterministic mood for previews and UI tests: the first keyword that
/// matches decides, anything else a mood picked by the words' bytes.
public struct MockMoodService: MoodService {
    public init() {}

    private static let keywords: [(Mood, [String])] = [
        (.joyful, ["happy", "joy", "fun", "sun", "laugh"]),
        (.calm, ["calm", "quiet", "slow", "peace", "rest"]),
        (.tender, ["love", "miss", "hug", "warm", "family"]),
        (.low, ["sad", "tired", "lonely", "rain", "cry"]),
        (.tense, ["stress", "angry", "worried", "deadline", "late"])
    ]

    public func mood(for text: String) async throws -> Mood {
        try await Task.sleep(for: .milliseconds(300))
        let lowered = text.lowercased()
        for (mood, words) in Self.keywords where words.contains(where: lowered.contains) {
            return mood
        }
        let sum = lowered.utf8.reduce(0) { $0 + Int($1) }
        return Mood.allCases[sum % Mood.allCases.count]
    }
}
