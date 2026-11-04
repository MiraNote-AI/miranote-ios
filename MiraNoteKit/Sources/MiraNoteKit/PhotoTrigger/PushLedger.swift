import Foundation

/// What the story's "..." menu did to a push.
public enum MenuAction: String, Codable, Sendable { case notThisDay, fewerLikeThis }

/// Why a scheduled push was taken back.
public enum RemovalReason: String, Codable, Sendable {
    case replaced, menuDay, menuBucket, replan, timeZone, clearAll, missing
}

/// One push, from being scheduled to what the user did with it. Place goes
/// by name only; no coordinates are kept.
public struct LedgerEntry: Codable, Equatable, Sendable {
    public var pushId: String
    /// The notification identifier: `"pt." + pushId`.
    public var identifier: String
    public var isDebug: Bool
    /// Belongs-to day ("yyyy-MM-dd").
    public var belongsTo: String
    public var groupKey: String
    /// PhotoKit localIdentifiers.
    public var photoIds: [String]
    public var bucket: PushBucket
    public var place: String?
    public var score: FragmentScore
    public var body: String
    public var questionId: String
    public var scheduledFor: Date
    public var deliveredAt: Date?
    public var notDeliveredReason: String?
    public var openedAt: Date?
    public var storyFinishedAt: Date?
    public var madePageAt: Date?
    public var menuAction: MenuAction?
    public var menuActionAt: Date?
    public var removedReason: RemovalReason?
    public var removedAt: Date?
    public var notOpened: Bool

    public init(pushId: String, isDebug: Bool = false, belongsTo: String, groupKey: String, photoIds: [String],
                bucket: PushBucket, place: String?, score: FragmentScore, body: String, questionId: String,
                scheduledFor: Date) {
        self.pushId = pushId
        self.identifier = "pt." + pushId
        self.isDebug = isDebug
        self.belongsTo = belongsTo
        self.groupKey = groupKey
        self.photoIds = photoIds
        self.bucket = bucket
        self.place = place
        self.score = score
        self.body = body
        self.questionId = questionId
        self.scheduledFor = scheduledFor
        self.notOpened = false
    }

    /// Scheduled and still waiting: not removed, not delivered, not a debug push.
    public var isActive: Bool {
        removedAt == nil && removedReason == nil && deliveredAt == nil && !isDebug
    }
}

/// The ledger as one JSON file (an array of entries) under Application
/// Support. A missing or damaged file loads as empty.
public struct PushLedgerStore: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/ledger.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("ledger.json")
    }

    public func load() -> [LedgerEntry] {
        guard let data = try? Data(contentsOf: file),
              let value = try? TriggerMemory.decoder.decode([LedgerEntry].self, from: data) else { return [] }
        return value
    }

    public func save(_ entries: [LedgerEntry]) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(entries).write(to: file, options: .atomic)
    }

    public func append(_ entry: LedgerEntry) throws {
        try save(load() + [entry])
    }

    /// Changes the entry with `pushId`; an unknown id changes nothing.
    public func update(_ pushId: String, _ change: (inout LedgerEntry) -> Void) throws {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.pushId == pushId }) else { return }
        change(&entries[index])
        try save(entries)
    }

    /// Every entry, pretty-printed, ISO 8601 dates.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(load())
    }
}

/// Settles the ledger with what the notification center says.
public enum LedgerReconciler {
    /// A delivered push unopened this long counts as "not opened".
    public static let openWindow: TimeInterval = 172_800

    /// A due entry that is no longer pending was delivered at `scheduledFor`
    /// (or, with notifications off, was not: reason `notificationsOff`).
    /// Delivered and unopened for 48 h: flagged `notOpened`, and its
    /// identifier returned so the caller clears it from the tray.
    public static func reconcile(_ entries: [LedgerEntry], now: Date, pending: Set<String>,
                                 notificationsAllowed: Bool) -> (entries: [LedgerEntry], clearDelivered: [String]) {
        var clear: [String] = []
        let settled = entries.map { entry -> LedgerEntry in
            var entry = entry
            guard entry.removedAt == nil, entry.removedReason == nil else { return entry }
            if entry.deliveredAt == nil, entry.scheduledFor <= now, !pending.contains(entry.identifier) {
                if notificationsAllowed {
                    entry.deliveredAt = entry.scheduledFor
                    entry.notDeliveredReason = nil
                } else {
                    entry.notDeliveredReason = "notificationsOff"
                }
            }
            if let delivered = entry.deliveredAt, entry.openedAt == nil,
               now.timeIntervalSince(delivered) >= openWindow {
                entry.notOpened = true
                clear.append(entry.identifier)
            }
            return entry
        }
        return (settled, clear)
    }

    /// Belongs-to days of delivered, non-debug pushes: a day is pushed once.
    public static func pushedDays(_ entries: [LedgerEntry]) -> Set<String> {
        Set(entries.filter { $0.deliveredAt != nil && !$0.isDebug }.map(\.belongsTo))
    }
}
