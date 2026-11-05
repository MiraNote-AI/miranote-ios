import Foundation

/// Per-photo analysis results, one small JSON file each under Application
/// Support (`PhotoTrigger/analysis/`): saving each photo as soon as it is
/// analysed is what lets an interrupted first run resume where it stopped.
/// Local only: Application Support is backed up by default, so the folder
/// is marked excluded from backup (handoff 7.2, "not in iCloud").
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
        try PhotoTriggerPaths.prepare(directory)
        try JSONEncoder().encode(analysis).write(to: file(for: analysis.id), options: .atomic)
    }

    /// Every saved result by photo id, in one pass over the folder (a file
    /// that no longer decodes is left out: the photo is analysed again).
    public func loadAll() -> [String: PhotoAnalysis] {
        var result: [String: PhotoAnalysis] = [:]
        for id in analyzedIds() {
            if let analysis = load(id) { result[id] = analysis }
        }
        return result
    }

    /// Drops the results and failures of every photo not in `ids` (deleted,
    /// or out of the window).
    public func prune(keeping ids: Set<String>) {
        for id in analyzedIds() where !ids.contains(id) {
            try? FileManager.default.removeItem(at: file(for: id))
        }
        let failures = failures()
        let kept = failures.filter { ids.contains($0.key) }
        if kept.count != failures.count { try? saveFailures(kept) }
    }

    /// Photos whose analysis failed (no local thumbnail, a Vision error, a
    /// timeout), by when they last failed. Kept beside the results under a
    /// name that is not `.json`, so it is never taken for one.
    public func failures() -> [String: Date] {
        guard let data = try? Data(contentsOf: failuresFile) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    public func saveFailures(_ failures: [String: Date]) throws {
        try PhotoTriggerPaths.prepare(directory)
        try PropertyListEncoder().encode(failures).write(to: failuresFile, options: .atomic)
    }

    private var failuresFile: URL { directory.appendingPathComponent("failures.plist") }

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

    /// Creates `directory` if needed and marks it excluded from backup, so
    /// nothing the trigger keeps leaves the phone.
    public static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = directory
        try marked.setResourceValues(values)
    }

    /// Moves `file` aside as `<name>.corrupt-<ms since 1970>`: what could
    /// not be read is kept for a look, and the next save starts a new file
    /// instead of writing over it.
    static func setAside(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        let name = "\(file.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970 * 1000))"
        var target = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(name)-\(UUID().uuidString)")
        }
        try? FileManager.default.moveItem(at: file, to: target)
    }
}

/// One element of a stored list or map, nil when it does not decode: a
/// row this build cannot read costs that row, not the file.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
