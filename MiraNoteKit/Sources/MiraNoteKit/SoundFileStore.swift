import Foundation

/// Stores recorded sound clips as files so `SoundClip.fileName` stays a
/// lightweight reference inside the persisted memory JSON.
public struct SoundFileStore: Sendable {
    private let directory: URL

    /// Defaults to Documents/MiraNoteSounds; tests pass a temp directory.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documents.appendingPathComponent("MiraNoteSounds", isDirectory: true)
        }
    }

    /// Writes the clip bytes and returns the file name to keep on the clip.
    @discardableResult
    public func save(_ data: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(id.uuidString).m4a"
        try data.write(to: directory.appendingPathComponent(fileName))
        return fileName
    }

    public func url(forFileName fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func exists(fileName: String) -> Bool {
        !fileName.isEmpty && FileManager.default.fileExists(atPath: url(forFileName: fileName).path)
    }

    public func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }
}
