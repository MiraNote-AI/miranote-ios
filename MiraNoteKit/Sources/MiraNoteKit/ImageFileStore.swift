import Foundation

/// Stores picked and generated images as files so `ImageRef.fileName` stays a
/// lightweight reference inside the persisted memory JSON (same shape as
/// SoundFileStore).
public struct ImageFileStore: Sendable {
    private let directory: URL

    /// Defaults to Documents/MiraNoteImages; tests pass a temp directory.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documents.appendingPathComponent("MiraNoteImages", isDirectory: true)
        }
    }

    /// Writes the image bytes and returns the file name to keep on the ref.
    @discardableResult
    public func save(_ data: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(id.uuidString).png"
        try data.write(to: directory.appendingPathComponent(fileName))
        return fileName
    }

    public func url(forFileName fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func data(forFileName fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: url(forFileName: fileName))
    }

    public func exists(fileName: String) -> Bool {
        !fileName.isEmpty && FileManager.default.fileExists(atPath: url(forFileName: fileName).path)
    }

    public func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }
}
