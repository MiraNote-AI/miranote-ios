import Foundation

/// A deleted page waiting in the 30-day bin (v2.1 "recently deleted":
/// losing a memory to a slip is a brand-level accident).
public struct TrashedMemory: Codable, Equatable, Sendable, Identifiable {
    public var memory: Memory
    public var collectionTitle: String
    public var deletedAt: Date

    public var id: Memory.ID { memory.id }

    public init(memory: Memory, collectionTitle: String, deletedAt: Date = .now) {
        self.memory = memory
        self.collectionTitle = collectionTitle
        self.deletedAt = deletedAt
    }
}

/// Everything the library persists: the shelf plus the bin. Older files
/// that stored a bare collections array still decode (empty bin).
public struct MemoryLibrary: Codable, Equatable, Sendable {
    public var collections: [MemoryCollection]
    public var trash: [TrashedMemory]

    public init(collections: [MemoryCollection] = [], trash: [TrashedMemory] = []) {
        self.collections = collections
        self.trash = trash
    }
}

/// Where the user's library lives. The app uses the file-backed store;
/// tests and previews use the in-memory one.
public protocol CollectionStore: Sendable {
    func load() -> MemoryLibrary
    func save(_ library: MemoryLibrary)
}

public extension MemoryCollection {
    /// First-launch content, so Home opens populated rather than blank.
    static var seed: [MemoryCollection] {
        [
            MemoryCollection(title: "Daily Log", memories: [
                Memory(title: "Lunch by the river", items: Memory.starterDraft()),
                Memory(title: "Slow morning, good coffee")
            ]),
            MemoryCollection(title: "Travel Scrapbook", memories: [
                Memory(title: "Noodle shop by the bridge")
            ]),
            MemoryCollection(title: "Food Diary", memories: [
                Memory(title: "Warm dumplings"),
                Memory(title: "Peach season")
            ]),
            MemoryCollection(title: "Little Joys", memories: [
                Memory(title: "Sunlight on the desk")
            ])
        ]
    }
}

/// Persists collections to a JSON file in the app's Documents directory. On a
/// fresh install (no file yet) it writes and returns the seed.
public struct FileCollectionStore: CollectionStore {
    private let url: URL

    public init(url: URL = FileCollectionStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("collections.json")
    }

    public func load() -> MemoryLibrary {
        guard let data = try? Data(contentsOf: url) else {
            let seeded = MemoryLibrary(collections: MemoryCollection.seed)
            save(seeded)
            return seeded
        }
        if let library = try? JSONDecoder().decode(MemoryLibrary.self, from: data) {
            return library
        }
        // Legacy file: a bare collections array from before the bin existed.
        if let legacy = try? JSONDecoder().decode([MemoryCollection].self, from: data) {
            return MemoryLibrary(collections: legacy)
        }
        let seeded = MemoryLibrary(collections: MemoryCollection.seed)
        save(seeded)
        return seeded
    }

    public func save(_ library: MemoryLibrary) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Non-persistent store for tests and previews; `save` is a no-op because the
/// view model already holds the live array.
public struct InMemoryCollectionStore: CollectionStore {
    private let initial: MemoryLibrary

    public init(collections: [MemoryCollection] = [], trash: [TrashedMemory] = []) {
        self.initial = MemoryLibrary(collections: collections, trash: trash)
    }

    public func load() -> MemoryLibrary { initial }

    public func save(_ library: MemoryLibrary) {}
}
