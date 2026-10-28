import Foundation
import Observation

/// Home screen: the user's note collections, loaded from and persisted to a
/// `CollectionStore`.
@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var library: MemoryLibrary
    private let store: CollectionStore

    public var collections: [MemoryCollection] { library.collections }
    public var trash: [TrashedMemory] { library.trash }

    /// App entry point: load (and seed on first run) from a store; pages
    /// past their 30 days in the bin are purged on the way in.
    public init(store: CollectionStore, now: Date = .now) {
        self.store = store
        var loaded = store.load()
        let cutoff = now.addingTimeInterval(-30 * 24 * 3600)
        let purged = loaded.trash.filter { $0.deletedAt > cutoff }
        if purged.count != loaded.trash.count {
            loaded.trash = purged
            store.save(loaded)
        }
        self.library = loaded
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
        library.collections.append(MemoryCollection(title: trimmed))
        store.save(library)
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
            let collectionIndex = library.collections.firstIndex(where: { $0.id == collectionID }),
            let noteIndex = library.collections[collectionIndex].memories
                .firstIndex(where: { $0.id == noteID })
        else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        library.collections[collectionIndex].memories[noteIndex].title = name.isEmpty ? "Untitled" : name
        library.collections[collectionIndex].memories[noteIndex].body = body
        library.collections[collectionIndex].memories[noteIndex].savedAt = .now
        store.save(library)
    }

    /// Filing a saved memory under a collection, creating it on first use.
    /// Saving the same memory again replaces its earlier copy in place, so
    /// repeated taps on Save never duplicate. Persists afterwards.
    public func file(_ memory: Memory, underCollectionTitled title: String) {
        for index in library.collections.indices {
            if let existing = library.collections[index].memories
                .firstIndex(where: { $0.id == memory.id }) {
                // The mood is the judge's to write: a copy filed from an
                // editor opened before the answer landed keeps the shelf's.
                let shelved = library.collections[index].memories[existing]
                var memory = memory
                memory.mood = shelved.mood
                memory.moodTextHash = shelved.moodTextHash
                // Opened and left without a change: still saved when it
                // was, so the star jar drops in only pages that changed.
                var unchanged = memory
                unchanged.savedAt = shelved.savedAt
                if unchanged == shelved { memory.savedAt = shelved.savedAt }
                library.collections[index].memories[existing] = memory
                store.save(library)
                return
            }
        }
        if let index = library.collections.firstIndex(where: { $0.title == title }) {
            library.collections[index].memories.append(memory)
        } else {
            library.collections.append(MemoryCollection(title: title, memories: [memory]))
        }
        store.save(library)
    }

    /// A page started in a journal ("+ New memory") goes to that journal by
    /// id: names are not unique. No journal, or one that is gone, files it
    /// under `title`. Filed already (autosave): replaced in place.
    public func file(_ memory: Memory, inCollection collectionID: MemoryCollection.ID?, orTitled title: String) {
        let filed = library.collections.contains { $0.memories.contains { $0.id == memory.id } }
        guard !filed, let index = library.collections.firstIndex(where: { $0.id == collectionID }) else {
            file(memory, underCollectionTitled: title)
            return
        }
        library.collections[index].memories.append(memory)
        store.save(library)
    }

    /// The page's "about" date is user-editable (v2.1): backfilled pages
    /// land in the month they are about, not the month they were made.
    public func setMemoryDate(
        _ noteID: Memory.ID,
        in collectionID: MemoryCollection.ID,
        to date: Date
    ) {
        guard
            let collectionIndex = library.collections.firstIndex(where: { $0.id == collectionID }),
            let noteIndex = library.collections[collectionIndex].memories
                .firstIndex(where: { $0.id == noteID })
        else { return }
        library.collections[collectionIndex].memories[noteIndex].memoryDate = date
        store.save(library)
    }

    /// A page on the shelf by id, wherever it is filed.
    public func memory(_ noteID: Memory.ID) -> Memory? {
        for collection in collections {
            if let memory = collection.memories.first(where: { $0.id == noteID }) { return memory }
        }
        return nil
    }

    /// Writes a judged mood, and the hash of the words it was judged from,
    /// onto the page as it is NOW: only those change, so an edit filed
    /// while the mood was on its way is kept (and, its words differing, is
    /// asked again). A page binned meanwhile is left alone.
    public func setMood(_ mood: Mood, judgedFrom textHash: String, for noteID: Memory.ID) {
        for index in library.collections.indices {
            if let note = library.collections[index].memories.firstIndex(where: { $0.id == noteID }) {
                library.collections[index].memories[note].mood = mood
                library.collections[index].memories[note].moodTextHash = textHash
                store.save(library)
                return
            }
        }
    }

    // MARK: Recently deleted (30-day bin) and moving

    /// Deleting a page moves it to the bin -- never straight to oblivion.
    public func deleteNote(_ noteID: Memory.ID, from collectionID: MemoryCollection.ID) {
        guard
            let collectionIndex = library.collections.firstIndex(where: { $0.id == collectionID }),
            let noteIndex = library.collections[collectionIndex].memories
                .firstIndex(where: { $0.id == noteID })
        else { return }
        let removed = library.collections[collectionIndex].memories.remove(at: noteIndex)
        library.trash.insert(TrashedMemory(
            memory: removed,
            collectionTitle: library.collections[collectionIndex].title
        ), at: 0)
        store.save(library)
    }

    /// Puts a binned page back into its old collection (recreating it by
    /// title when it no longer exists).
    public func restore(_ trashedID: Memory.ID) {
        guard let index = library.trash.firstIndex(where: { $0.id == trashedID }) else { return }
        let entry = library.trash.remove(at: index)
        if let target = library.collections.firstIndex(where: { $0.title == entry.collectionTitle }) {
            library.collections[target].memories.append(entry.memory)
        } else {
            library.collections.append(
                MemoryCollection(title: entry.collectionTitle, memories: [entry.memory])
            )
        }
        store.save(library)
    }

    /// Long-press "Move to...": one page, one home (v2.1 one-journal rule).
    public func move(
        _ noteID: Memory.ID,
        from sourceID: MemoryCollection.ID,
        to destinationID: MemoryCollection.ID
    ) {
        guard sourceID != destinationID,
              let sourceIndex = library.collections.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = library.collections.firstIndex(where: { $0.id == destinationID }),
              let noteIndex = library.collections[sourceIndex].memories
                .firstIndex(where: { $0.id == noteID })
        else { return }
        let moved = library.collections[sourceIndex].memories.remove(at: noteIndex)
        library.collections[destinationIndex].memories.append(moved)
        store.save(library)
    }
}
