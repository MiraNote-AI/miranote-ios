import Foundation

/// One fragment of the last run as the debug page lists it.
public struct FragmentReport: Codable, Equatable, Sendable {
    public let groupKey: String
    public let belongsTo: String
    /// Every photo, duplicates included, in time order.
    public let photoIds: [String]
    public let rawCount: Int
    public let uniqueCount: Int
    /// The score at the first slot; nil when a hard rule rules it out.
    public let score: FragmentScore?
    public let bucket: PushBucket
    /// Why it may not go out in the first slot; nil when it may.
    public let ineligible: Ineligible?
    /// `AIResultCache.key` of its preselected photos.
    public let cacheKey: String
}

/// What the last run left for the debug page, kept in memory and in a
/// small file so the page has something after a relaunch.
public struct LastRunReport: Codable, Equatable, Sendable {
    public let finishedAt: Date
    /// Slot day -> why nothing is scheduled.
    public let emptyDays: [String: String]
    public let fragments: [FragmentReport]
    /// Photos left out as documents and the like.
    public let utility: [String]
    public let categories: CategoryReport
    public let threshold: ThresholdResult?
}

/// The last run's report as one JSON file. A missing or damaged file loads as nil.
public struct LastRunStore: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/last-run.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("last-run.json")
    }

    public func load() -> LastRunReport? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? TriggerMemory.decoder.decode(LastRunReport.self, from: data)
    }

    public func save(_ report: LastRunReport) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(report).write(to: file, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}

/// What the AI said about a fragment's photo set.
public enum AIStatus: Equatable, Sendable {
    case ok
    case rejected(String)
    case notSent
}

/// Everything the debug page shows (handoff 6.8).
public struct SchedulerSnapshot: Equatable, Sendable {
    /// One of the next seven nights.
    public struct Day: Equatable, Sendable {
        public let slot: Date
        public let slotDay: String
        /// The active push for the night, if any.
        public let entry: LedgerEntry?
        /// Why the night is empty (the last run's reason), when it is.
        public let emptyReason: String?
    }

    /// A fragment of the last run, with what has become of it since.
    public struct Group: Equatable, Sendable {
        public let report: FragmentReport
        /// The slot day of its active push, if scheduled.
        public let scheduledDay: String?
        public let aiStatus: AIStatus
    }

    public let days: [Day]
    /// Newest first.
    public let runs: [ScheduleRun]
    public let counters: ScheduleCounters
    public let preferences: PushPreferences
    public let groups: [Group]
    public let utilityPhotoIds: [String]
    public let categories: CategoryReport
    public let threshold: ThresholdResult?
    public let isRunning: Bool
}

/// What "preview the scheduled push" did.
public enum PreviewResult: Equatable, Sendable {
    /// A copy of that night's push goes out in 10 s.
    case scheduled(slotDay: String)
    case nothingScheduled
    case notificationsOff
}
