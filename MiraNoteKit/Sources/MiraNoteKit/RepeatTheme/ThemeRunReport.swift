import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What started a theme run.
public enum ThemeTrigger: String, Codable, Sendable {
    case foreground, background, debug
}

/// One theme run, for the debug page (spec 6.2 asks for the measured time
/// and memory of a regroup). Local only, like every theme file.
public struct ThemeRunReport: Codable, Equatable, Sendable {
    public var at: Date
    public var trigger: ThemeTrigger
    /// Photos the library gave for the window.
    public var photos: Int
    /// Checkups this run made.
    public var checkedNew: Int
    /// Moments clustered (after the cap); 0 when the run stopped before.
    public var moments: Int
    public var piles: [Pile]
    /// Wall time of the checkup and of moments + tree + cut, measured.
    public var checkupMs: Int
    public var clusterMs: Int
    /// The process's peak physical footprint after clustering; nil when it
    /// could not be read.
    public var peakMemoryMB: Double?
    /// Round-1 calls sent (a stored answer reused is not one).
    public var asked: Int
    /// Short, readable reasons: a failed round, a stop before clustering.
    public var failures: [String]

    public init(at: Date, trigger: ThemeTrigger, photos: Int, checkedNew: Int, moments: Int, piles: [Pile],
                checkupMs: Int, clusterMs: Int, peakMemoryMB: Double?, asked: Int, failures: [String]) {
        self.at = at
        self.trigger = trigger
        self.photos = photos
        self.checkedNew = checkedNew
        self.moments = moments
        self.piles = piles
        self.checkupMs = checkupMs
        self.clusterMs = clusterMs
        self.peakMemoryMB = peakMemoryMB
        self.asked = asked
        self.failures = failures
    }

    private enum CodingKeys: String, CodingKey {
        case at, trigger, photos, checkedNew, moments, piles, checkupMs, clusterMs, peakMemoryMB, asked, failures
    }

    /// A pile as `runs.json` keeps it: without its center (768 floats a
    /// pile, which the debug page never shows). It loads with an empty one.
    private struct StoredPile: Codable {
        let momentIds: [String]
        let days: Int
        let maxDayShare: Double
        let height: Float
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Date.self, forKey: .at)
        trigger = try container.decode(ThemeTrigger.self, forKey: .trigger)
        photos = try container.decode(Int.self, forKey: .photos)
        checkedNew = try container.decode(Int.self, forKey: .checkedNew)
        moments = try container.decode(Int.self, forKey: .moments)
        piles = try container.decode([StoredPile].self, forKey: .piles).map {
            Pile(momentIds: $0.momentIds, days: $0.days, maxDayShare: $0.maxDayShare, height: $0.height, center: [])
        }
        checkupMs = try container.decode(Int.self, forKey: .checkupMs)
        clusterMs = try container.decode(Int.self, forKey: .clusterMs)
        peakMemoryMB = try container.decodeIfPresent(Double.self, forKey: .peakMemoryMB)
        asked = try container.decode(Int.self, forKey: .asked)
        failures = try container.decode([String].self, forKey: .failures)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(photos, forKey: .photos)
        try container.encode(checkedNew, forKey: .checkedNew)
        try container.encode(moments, forKey: .moments)
        try container.encode(piles.map {
            StoredPile(momentIds: $0.momentIds, days: $0.days, maxDayShare: $0.maxDayShare, height: $0.height)
        }, forKey: .piles)
        try container.encode(checkupMs, forKey: .checkupMs)
        try container.encode(clusterMs, forKey: .clusterMs)
        try container.encodeIfPresent(peakMemoryMB, forKey: .peakMemoryMB)
        try container.encode(asked, forKey: .asked)
        try container.encode(failures, forKey: .failures)
    }

    /// The process's peak physical footprint (`task_vm_info`), in MB.
    static func peakMemoryMB() -> Double? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.ledger_phys_footprint_peak) / 1_048_576
        #else
        return nil
        #endif
    }
}

/// `themes/runs.json`: the last 20 run reports.
public struct ThemeRunLog: Sendable {
    static let maxEntries = 20
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("runs.json")
    }

    public func load() -> [ThemeRunReport] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let stored = try? decoder.decode(LenientFile.self, from: data) {
            return stored.runs.compactMap(\.value)
        }
        PhotoTriggerPaths.setAside(file)
        return []
    }

    public func append(_ report: ThemeRunReport) throws {
        let kept = Array((load() + [report]).suffix(Self.maxEntries))
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(runs: kept)).write(to: file, options: .atomic)
    }

    private struct File: Encodable {
        let version = 1
        let runs: [ThemeRunReport]
    }

    private struct LenientFile: Decodable {
        let runs: [Lenient<ThemeRunReport>]
    }
}

/// Everything the debug page "Themes" shows.
public struct ThemeSnapshot: Equatable, Sendable {
    /// Oldest first.
    public var runs: [ThemeRunReport]
    /// Tonight's piles (the last run that clustered, in this process).
    public var piles: [Pile]
    /// Big theme id -> the index in `piles` of the pile it follows.
    public var follows: [String: Int]
    public var themes: [ThemeRow]
    /// Oldest first.
    public var rounds: [RoundLogEntry]
    /// Theme id -> how many different local days its members (with a theme
    /// record) were taken on.
    public var days: [String: Int]

    public init(runs: [ThemeRunReport], piles: [Pile], follows: [String: Int], themes: [ThemeRow],
                rounds: [RoundLogEntry], days: [String: Int] = [:]) {
        self.runs = runs
        self.piles = piles
        self.follows = follows
        self.themes = themes
        self.rounds = rounds
        self.days = days
    }
}
