import Foundation
import Observation

/// Home screen (sketch 1): collections row, "Start a memory", bottom pill.
@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var collections: [MemoryCollection]

    public init(collections: [MemoryCollection] = []) {
        self.collections = collections
    }

    /// D3: Home shows an empty-state hint instead of onboarding.
    public var showsEmptyStateHint: Bool { collections.isEmpty }

    /// "Start a memory" -> a fresh canvas-ready Memory.
    public func startMemory() -> Memory {
        Memory(createdAt: .now)
    }

    /// Filing a saved memory under a collection, creating it on first use.
    /// Saving the same memory again replaces its earlier copy in place, so
    /// repeated taps on Save never duplicate.
    public func file(_ memory: Memory, underCollectionTitled title: String) {
        for index in collections.indices {
            if let existing = collections[index].memories.firstIndex(where: { $0.id == memory.id }) {
                collections[index].memories[existing] = memory
                return
            }
        }
        if let index = collections.firstIndex(where: { $0.title == title }) {
            collections[index].memories.append(memory)
        } else {
            collections.append(MemoryCollection(title: title, memories: [memory]))
        }
    }
}
