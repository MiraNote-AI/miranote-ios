import Foundation

/// What the story's "..." menu changed: days never pushed again and
/// buckets shown less for a while.
public struct PushPreferences: Codable, Equatable, Sendable {
    /// Belongs-to day ("yyyy-MM-dd") -> when it was blocked.
    public var blockedDays: [String: Date]
    /// Blocked day -> the blocked push's photos (localIdentifiers). Day keys
    /// are local dates of the zone they were written in: after a time-zone
    /// change the same photos may fall on another day, and still stay out.
    public var blockedPhotos: [String: [String]]
    /// Bucket -> when "fewer like this" was chosen.
    public var fewer: [PushBucket: Date]

    /// "Fewer" blocks a bucket this long, then x0.6.
    static let fewerBlockSeconds: TimeInterval = 30 * 86_400
    static let fewerMultiplier = 0.6

    public init(blockedDays: [String: Date] = [:], blockedPhotos: [String: [String]] = [:],
                fewer: [PushBucket: Date] = [:]) {
        self.blockedDays = blockedDays
        self.blockedPhotos = blockedPhotos
        self.fewer = fewer
    }

    public func isBlocked(_ day: String) -> Bool {
        blockedDays[day] != nil
    }

    /// The day is blocked, or any of the photos was in a blocked push.
    public func isBlocked(_ day: String, photoIds: [String]) -> Bool {
        guard !isBlocked(day) else { return true }
        return blockedPhotos.values.contains { !Set($0).isDisjoint(with: photoIds) }
    }

    /// nil while the bucket is blocked (under 30 days since "fewer"), 0.6
    /// afterwards, 1.0 when not set. `.other` is never reduced.
    public func multiplier(for bucket: PushBucket, at date: Date) -> Double? {
        guard bucket != .other, let since = fewer[bucket] else { return 1.0 }
        return date.timeIntervalSince(since) < Self.fewerBlockSeconds ? nil : Self.fewerMultiplier
    }

    private enum CodingKeys: String, CodingKey { case blockedDays, blockedPhotos, fewer }

    // Bucket-keyed dictionaries encode as arrays by default: use string keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockedDays = try container.decodeIfPresent([String: Date].self, forKey: .blockedDays) ?? [:]
        // Written before blocked photos: the days alone.
        blockedPhotos = try container.decodeIfPresent([String: [String]].self, forKey: .blockedPhotos) ?? [:]
        let raw = try container.decodeIfPresent([String: Date].self, forKey: .fewer) ?? [:]
        fewer = Dictionary(uniqueKeysWithValues: raw.compactMap { key, date in
            PushBucket(rawValue: key).map { ($0, date) }
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockedDays, forKey: .blockedDays)
        try container.encode(blockedPhotos, forKey: .blockedPhotos)
        try container.encode(Dictionary(uniqueKeysWithValues: fewer.map { ($0.key.rawValue, $0.value) }),
                             forKey: .fewer)
    }
}

/// The preferences as one JSON file under Application Support. A missing
/// or damaged file loads as empty.
public struct PushPreferencesStore: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/preferences.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("preferences.json")
    }

    public func load() -> PushPreferences {
        guard let data = try? Data(contentsOf: file),
              let value = try? TriggerMemory.decoder.decode(PushPreferences.self, from: data) else {
            return PushPreferences()
        }
        return value
    }

    public func save(_ preferences: PushPreferences) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(preferences).write(to: file, options: .atomic)
    }

    /// Deletes the file (back to empty).
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    public func update(_ change: (inout PushPreferences) -> Void) throws {
        var value = load()
        change(&value)
        try save(value)
    }
}
