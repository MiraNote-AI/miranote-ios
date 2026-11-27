import Foundation

/// A round-1 ask whose answer could not be used.
struct FailedAsk: Codable, Equatable, Sendable {
    let at: Date
    let photoIds: [String]
}

/// `themes/failed-asks.json`: asks whose answer was unusable. The same pile
/// is not asked again for 7 days, unless it grew to 1.5x the photos of the
/// failed ask.
public struct ThemeAskCooldownStore: Sendable {
    static let cooldown: TimeInterval = 7 * 86_400
    static let growthFactor = 1.5
    static let minCoverage = 0.5
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("failed-asks.json")
    }

    func load() -> [FailedAsk] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let stored = try? decoder.decode(LenientFile.self, from: data) {
            return stored.entries.compactMap(\.value)
        }
        PhotoTriggerPaths.setAside(file)
        return []
    }

    func record(_ ask: FailedAsk) throws {
        let kept = (load() + [ask]).filter { ask.at.timeIntervalSince($0.at) < Self.cooldown }
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(entries: kept)).write(to: file, options: .atomic)
    }

    func isCooling(photoIds: [String], now: Date) -> Bool {
        guard !photoIds.isEmpty else { return false }
        let tonight = Set(photoIds)
        return load().contains { entry in
            guard now.timeIntervalSince(entry.at) < Self.cooldown else { return false }
            let covered = Double(tonight.intersection(entry.photoIds).count)
            return covered >= Self.minCoverage * Double(tonight.count)
                && Double(tonight.count) < Self.growthFactor * Double(entry.photoIds.count)
        }
    }

    private struct File: Encodable {
        let version = 1
        let entries: [FailedAsk]
    }

    private struct LenientFile: Decodable {
        let entries: [Lenient<FailedAsk>]
    }
}
