import Foundation

/// Where photo-trigger memories come from. v0 has only the bundled demo; the
/// backend version returns the same `TriggerMemory` and its photos' URLs.
public protocol TriggerMemorySource: Sendable {
    /// The memory to surface, or nil when there is none.
    func load() -> TriggerMemory?
    /// A local file URL for one of the memory's photos.
    func url(for photo: TriggerMemory.Photo) -> URL?
}

/// Reads `memory.json` and its photos from a folder bundled with the app
/// (`DemoMemory`, built from the untracked `demo-input/`). A build without the
/// folder, or with a file that does not decode, simply has no memory.
public struct DemoMemoryLoader: TriggerMemorySource {
    public let directory: URL?

    public init(bundle: Bundle = .main, folder: String = "DemoMemory") {
        directory = bundle.url(forResource: folder, withExtension: nil)
    }

    public init(directory: URL?) {
        self.directory = directory
    }

    public func load() -> TriggerMemory? {
        guard let file = directory?.appendingPathComponent("memory.json"),
              let data = try? Data(contentsOf: file),
              let memory = try? TriggerMemory.decode(data),
              !memory.story.photos.isEmpty
        else { return nil }
        return memory
    }

    public func url(for photo: TriggerMemory.Photo) -> URL? {
        guard let file = photo.file, let url = directory?.appendingPathComponent(file),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}
