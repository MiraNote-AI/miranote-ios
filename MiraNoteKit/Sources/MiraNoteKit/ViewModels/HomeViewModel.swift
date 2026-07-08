import Foundation
import Observation

/// Home screen: the user's note collections, loaded from and persisted to a
/// `CollectionStore`.
@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var collections: [MemoryCollection]
    private let store: CollectionStore

    /// App entry point: load (and seed on first run) from a store.
    public init(store: CollectionStore) {
        self.store = store
        self.collections = store.load()
    }

    /// Test/preview entry point: start from a fixed in-memory list.
    public convenience init(collections: [MemoryCollection] = []) {
        self.init(store: InMemoryCollectionStore(collections: collections))
    }

    /// D3: Home shows an empty-state hint instead of onboarding.
    public var showsEmptyStateHint: Bool { collections.isEmpty }

    /// "Start a memory" -> a fresh canvas-ready Memory.
    public func startMemory() -> Memory { Memory(createdAt: .now) }

    /// The current version of a collection by id (so a pushed detail view can
    /// re-read after an edit).
    public func collection(_ id: MemoryCollection.ID) -> MemoryCollection? {
        collections.first { $0.id == id }
    }

    /// Create a new, empty collection and persist.
    public func addCollection(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections.append(MemoryCollection(title: trimmed))
        store.save(collections)
    }

    /// Add a note to a collection by id and persist.
    public func addNote(titled title: String, to collectionID: MemoryCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        collections[index].memories.append(Memory(title: name.isEmpty ? "New note" : name))
        store.save(collections)
    }

    /// A single note, looked up within a collection.
    public func note(_ noteID: Memory.ID, in collectionID: MemoryCollection.ID) -> Memory? {
        collections.first { $0.id == collectionID }?.memories.first { $0.id == noteID }
    }

    /// Update a note's title and body in place and persist.
    public func updateNote(
        _ noteID: Memory.ID,
        in collectionID: MemoryCollection.ID,
        title: String,
        body: String
    ) {
        guard
            let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }),
            let noteIndex = collections[collectionIndex].memories.firstIndex(where: { $0.id == noteID })
        else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        collections[collectionIndex].memories[noteIndex].title = name.isEmpty ? "Untitled" : name
        collections[collectionIndex].memories[noteIndex].body = body
        collections[collectionIndex].memories[noteIndex].savedAt = .now
        store.save(collections)
    }

    /// Filing a saved memory under a collection, creating it on first use.
    /// Saving the same memory again replaces its earlier copy in place, so
    /// repeated taps on Save never duplicate. Persists afterwards.
    public func file(_ memory: Memory, underCollectionTitled title: String) {
        for index in collections.indices {
            if let existing = collections[index].memories.firstIndex(where: { $0.id == memory.id }) {
                collections[index].memories[existing] = memory
                store.save(collections)
                return
            }
        }
        if let index = collections.firstIndex(where: { $0.title == title }) {
            collections[index].memories.append(memory)
        } else {
            collections.append(MemoryCollection(title: title, memories: [memory]))
        }
        store.save(collections)
    }
}
