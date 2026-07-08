import Foundation

/// Where the user's note collections live. The app uses the file-backed store;
/// tests and previews use the in-memory one.
public protocol CollectionStore: Sendable {
    func load() -> [MemoryCollection]
    func save(_ collections: [MemoryCollection])
}

public extension MemoryCollection {
    /// First-launch content, so Home opens populated rather than blank.
    static var seed: [MemoryCollection] {
        [
            MemoryCollection(title: "Daily Log", memories: [
                Memory(title: "Lunch by the river"),
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

    public func load() -> [MemoryCollection] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([MemoryCollection].self, from: data)
        else {
            let seed = MemoryCollection.seed
            save(seed)
            return seed
        }
        return decoded
    }

    public func save(_ collections: [MemoryCollection]) {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Non-persistent store for tests and previews; `save` is a no-op because the
/// view model already holds the live array.
public struct InMemoryCollectionStore: CollectionStore {
    private let initial: [MemoryCollection]

    public init(collections: [MemoryCollection] = []) {
        self.initial = collections
    }

    public func load() -> [MemoryCollection] { initial }

    public func save(_ collections: [MemoryCollection]) {}
}
