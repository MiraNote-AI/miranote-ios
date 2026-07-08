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

        var scored: [(hit: PageHit, score: Int)] = []
        for collection in library.collections {
            for memory in collection.memories {
                let titleText = memory.title.lowercased()
                let haystack = searchText(of: memory)
                var score = 0
                for token in tokens {
                    if titleText.contains(token) { score += 3 }
                    if haystack.contains(token) { score += 1 }
                }
                if score > 0 {
                    scored.append((PageHit(collectionID: collection.id, memory: memory), score))
                }
            }
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
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

    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}
