import CryptoKit
import Foundation

/// What the backend said about a group: a memory, or a refusal. Only these
/// two are ever cached (a network error is retried, never remembered).
public enum AIVerdict: Codable, Equatable, Sendable {
    case ok(memory: TriggerMemory, photoIds: [String: String])
    case rejected(reason: String, message: String)

    /// A memory the fake AI made: never stored, read as absent.
    var isFakeMade: Bool {
        if case .ok(let memory, _) = self { return memory.isFakeMade }
        return false
    }

    /// A memory the backend wrote under other copy rules than the phone's
    /// (`generation.copyVersion`): never stored, or the phone's key would
    /// keep words of the old rules.
    var isOtherCopy: Bool {
        if case .ok(let memory, _) = self, let generation = memory.generation {
            return generation.copyVersion != TriggerMemory.copyVersion
        }
        return false
    }
}

/// AI verdicts by photo set, so the same photos never cost a second call.
/// One JSON file; a missing file loads as empty, an entry that does not
/// decode is skipped, and a damaged file is moved aside before anything
/// is written over it (as `PushLedgerStore`). A memory the
/// fake AI made, stored by an older build, reads as absent: the backend is
/// asked again and its answer takes the key.
public struct AIResultCache: Sendable {
    private struct Entry: Codable {
        var verdict: AIVerdict
        var belongsTo: String
        var storedAt: Date
    }

    /// Entries older than this (by belongs-to day) are purged.
    static let keepDays = 60

    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/ai-cache.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("ai-cache.json")
    }

    /// SHA-256 hex of the copy version and the sorted localIdentifiers,
    /// joined by newlines: words written under older copy rules are never
    /// reused (handoff refine 5.4).
    public static func key(_ localIdentifiers: [String], copyVersion: String = TriggerMemory.copyVersion) -> String {
        let joined = ([copyVersion] + localIdentifiers.sorted()).joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func verdict(_ key: String) -> AIVerdict? {
        load()[key].flatMap { $0.verdict.isFakeMade ? nil : $0.verdict }
    }

    /// A memory written under other copy rules is not stored.
    public func store(_ verdict: AIVerdict, key: String, belongsTo: String, at: Date) throws {
        guard !verdict.isOtherCopy else { return }
        var all = load()
        all[key] = Entry(verdict: verdict, belongsTo: belongsTo, storedAt: at)
        try save(all)
    }

    /// Every stored verdict by key, read once.
    public func verdicts() -> [String: AIVerdict] {
        load().compactMapValues { $0.verdict.isFakeMade ? nil : $0.verdict }
    }

    /// Deletes the file (back to empty).
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// Drops entries whose belongs-to day is more than 60 days before `today`.
    public func purge(today: String) throws {
        guard let limit = Self.dayNumber(today).map({ $0 - Self.keepDays }) else { return }
        let all = load()
        let kept = all.filter { entry in
            guard let day = Self.dayNumber(entry.value.belongsTo) else { return true }
            return day >= limit
        }
        if kept.count != all.count { try save(kept) }
    }

    /// Whole days since 1970 of a "yyyy-MM-dd" string.
    private static func dayNumber(_ day: String) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return Int(date.timeIntervalSince1970 / 86_400)
    }

    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        guard let all = try? TriggerMemory.decoder.decode([String: Lenient<Entry>].self, from: data) else {
            PhotoTriggerPaths.setAside(file)
            return [:]
        }
        let entries = all.compactMapValues(\.value)
        if entries.count < all.count {
            PhotoTriggerPaths.setAside(file)
            try? save(entries)
        }
        return entries
    }

    private func save(_ entries: [String: Entry]) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(entries).write(to: file, options: .atomic)
    }
}
