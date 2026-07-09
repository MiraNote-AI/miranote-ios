import Foundation

/// A page matched by a search, addressed within its journal.
public struct PageHit: Equatable, Sendable, Identifiable {
    public let collectionID: MemoryCollection.ID
    public let memory: Memory

    public var id: Memory.ID { memory.id }

    public init(collectionID: MemoryCollection.ID, memory: Memory) {
        self.collectionID = collectionID
        self.memory = memory
    }
}

/// The v2.1 "ask the past" search, local edition: deterministic, offline,
/// covering titles, bodies, canvas text, and sound notes. The :8004
/// semantic layer takes over per-note once the backend grows a user-notes
/// namespace (recorded roadmap item); the UI contract stays the same.
public enum LibrarySearch {
    public static func find(_ query: String, in library: MemoryLibrary, limit: Int = 6) -> [PageHit] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        var scored: [ScoredHit] = []
        for collection in library.collections {
            for memory in collection.memories {
                let titleText = memory.title.lowercased()
                let haystack = searchText(of: memory)
                var titleScore = 0
                var bodyScore = 0
                for token in tokens {
                    if titleText.contains(token) { titleScore += 1 }
                    if haystack.contains(token) { bodyScore += 1 }
                }
                if titleScore + bodyScore > 0 {
                    scored.append(ScoredHit(
                        hit: PageHit(collectionID: collection.id, memory: memory),
                        titleScore: titleScore,
                        bodyScore: bodyScore
                    ))
                }
            }
        }
        // Title matches rank first as a rule, not a weight: any title hit
        // outranks any number of body-only hits.
        return scored
            .sorted {
                if $0.titleScore != $1.titleScore { return $0.titleScore > $1.titleScore }
                if $0.bodyScore != $1.bodyScore { return $0.bodyScore > $1.bodyScore }
                return $0.hit.memory.memoryDate > $1.hit.memory.memoryDate
            }
            .prefix(limit)
            .map(\.hit)
    }

    /// Everything a page "says": title, body, canvas text, sound notes.
    private static func searchText(of memory: Memory) -> String {
        var parts = [memory.title, memory.body]
        for item in memory.items {
            switch item.content {
            case .text(let block):
                parts.append(block.text)
            case .sound(let clip):
                parts.append(clip.note)
            case .sticker(let sticker):
                parts.append(sticker.prompt)
            case .image(let ref):
                parts.append(ref.displayName)
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private struct ScoredHit {
        let hit: PageHit
        let titleScore: Int
        let bodyScore: Int
    }

    /// English function words carry no content: without this, a chatty
    /// message like "can you help me..." matches any page whose body says
    /// "you". CJK single characters are content words and stay untouched.
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "not", "no",
        "of", "to", "in", "on", "at", "for", "with", "about", "from", "by", "as",
        "is", "are", "was", "were", "be", "been", "am",
        "do", "does", "did", "have", "has", "had",
        "can", "could", "will", "would", "should", "shall", "may", "might", "must",
        "i", "me", "my", "mine", "you", "your", "yours",
        "we", "us", "our", "he", "she", "it", "its", "they", "them", "their",
        "this", "that", "these", "those", "there", "here",
        "what", "when", "where", "which", "who", "whom", "why", "how",
        "any", "all", "some", "please", "help"
    ]

    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                // Single ASCII characters are noise ("a", "5"), but a single
                // CJK character is a whole word -- it must survive.
                token.count > 1 || (token.first.map { !$0.isASCII } ?? false)
            }
            .filter { !stopwords.contains($0) }
    }
}
