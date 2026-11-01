import Foundation

/// Per-photo analysis results, one small JSON file each under Application
/// Support (`PhotoTrigger/analysis/`): saving each photo as soon as it is
/// analysed is what lets an interrupted first run resume where it stopped.
/// Local only -- not in Documents, so not in iCloud backups of the journal.
public struct AnalysisStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/PhotoTrigger/analysis`.
    public static var defaultDirectory: URL {
        PhotoTriggerPaths.root.appendingPathComponent("analysis", isDirectory: true)
    }

    public func load(_ id: String) -> PhotoAnalysis? {
        guard let data = try? Data(contentsOf: file(for: id)) else { return nil }
        return try? JSONDecoder().decode(PhotoAnalysis.self, from: data)
    }

    public func save(_ analysis: PhotoAnalysis) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(analysis).write(to: file(for: analysis.id), options: .atomic)
    }

    /// Every photo with a saved result, read from the file names alone.
    public func analyzedIds() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap(Self.id(fromFileName:)))
    }

    // localIdentifiers hold slashes: names are the id in URL-safe base64.
    private func file(for id: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: id))
    }

    static func fileName(for id: String) -> String {
        Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + ".json"
    }

    static func id(fromFileName name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        var base = String(name.dropLast(5))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Where the photo trigger keeps its files: `Application Support/PhotoTrigger`.
public enum PhotoTriggerPaths {
    public static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PhotoTrigger", isDirectory: true)
    }
}
