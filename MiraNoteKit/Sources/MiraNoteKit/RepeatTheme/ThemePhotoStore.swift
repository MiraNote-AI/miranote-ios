import Foundation

/// Theme photo records, one JSON file per local calendar month under
/// Application Support (`PhotoTrigger/themes/photos/2026-11.json`): a library
/// can hold thousands of photos at about 3 KB of print each, so a save
/// rewrites one month, not the whole set. Every id lives in exactly one file.
/// Local only, and excluded from backup like the rest of the trigger's files.
public struct ThemePhotoStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/PhotoTrigger/themes/photos`.
    public static var defaultDirectory: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("photos", isDirectory: true)
    }

    /// Every stored photo by id. A month file that does not decode loads
    /// empty; a row that does not decode costs only that row.
    public func loadAll() -> [String: ThemePhoto] {
        var result: [String: ThemePhoto] = [:]
        for name in monthFileNames() {
            for photo in read(directory.appendingPathComponent(name)) ?? [] { result[photo.id] = photo }
        }
        return result
    }

    /// Adds or replaces `photos`, rewriting only the months they land in. A
    /// photo already stored in another month (its date moved) is taken out of
    /// that file.
    public func upsert(_ photos: [ThemePhoto], calendar: Calendar) throws {
        guard !photos.isEmpty else { return }
        try PhotoTriggerPaths.prepare(directory)
        let incoming = Set(photos.map(\.id))
        var byMonth: [String: [ThemePhoto]] = [:]
        for photo in photos { byMonth[Self.monthName(photo.takenAt, calendar), default: []].append(photo) }
        for name in monthFileNames() where byMonth[name] == nil {
            let url = directory.appendingPathComponent(name)
            guard let stored = read(url) else { continue }
            let kept = stored.filter { !incoming.contains($0.id) }
            if kept.count != stored.count { try write(kept, to: url) }
        }
        for (name, added) in byMonth {
            let url = directory.appendingPathComponent(name)
            let kept = (existing(url)).filter { !incoming.contains($0.id) }
            try write(kept + added, to: url)
        }
    }

    /// Drops `ids`, rewriting only the months that held them.
    public func remove(_ ids: Set<String>, calendar: Calendar) throws {
        try drop { ids.contains($0.id) }
    }

    /// Drops every photo whose id is not in `ids` (deleted from the library).
    public func prune(keeping ids: Set<String>) throws {
        try drop { !ids.contains($0.id) }
    }

    private func drop(where isDropped: (ThemePhoto) -> Bool) throws {
        for name in monthFileNames() {
            let url = directory.appendingPathComponent(name)
            guard let stored = read(url) else { continue }
            let kept = stored.filter { !isDropped($0) }
            guard kept.count != stored.count else { continue }
            if kept.isEmpty {
                try FileManager.default.removeItem(at: url)
            } else {
                try write(kept, to: url)
            }
        }
    }

    // MARK: - Files

    private struct File: Encodable {
        let version = 1
        let photos: [ThemePhoto]
    }

    private struct LenientFile: Decodable {
        let photos: [Lenient<ThemePhoto>]
    }

    private static func monthName(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d.json", parts.year ?? 0, parts.month ?? 0)
    }

    private static func isMonthFile(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}\.json$"#, options: .regularExpression) != nil
    }

    private func monthFileNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isMonthFile).sorted()
    }

    /// The rows of a month file; nil when it is missing or does not decode.
    private func read(_ url: URL) -> [ThemePhoto]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(LenientFile.self, from: data) else { return nil }
        return file.photos.compactMap(\.value)
    }

    /// Rows to build a save on: none when the file is new, and none (with
    /// the file set aside for a look) when it is there but unreadable.
    private func existing(_ url: URL) -> [ThemePhoto] {
        if let rows = read(url) { return rows }
        if FileManager.default.fileExists(atPath: url.path) { PhotoTriggerPaths.setAside(url) }
        return []
    }

    private func write(_ photos: [ThemePhoto], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let sorted = photos.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        try encoder.encode(File(photos: sorted)).write(to: url, options: .atomic)
    }
}
