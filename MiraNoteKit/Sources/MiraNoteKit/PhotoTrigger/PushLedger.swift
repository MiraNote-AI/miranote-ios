import Foundation

/// What the story's "..." menu did to a push: a life fragment's day or
/// bucket, a repeat push's theme.
public enum MenuAction: String, Codable, Sendable { case notThisDay, fewerLikeThis, notThisTheme }

/// Why a scheduled push was taken back.
public enum RemovalReason: String, Codable, Sendable {
    case replaced, menuDay, menuBucket, replan, timeZone, clearAll, missing
    /// The app now runs as an App Store install (decision 8).
    case appStore
    /// A TestFlight tester turned the Settings switch off (or never on).
    case optedOut
    /// Written under older copy rules: composed again (handoff refine 5.4).
    case copyUpgrade
    /// Written by the fake AI, now switched off: composed again.
    case fakeAIOff
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
    /// The question the push asks, as picked for its night; nil in
    /// entries written before question types.
    public var question: String?
    /// Its type id (`QuestionPicker`); nil in entries written before types.
    public var questionType: String?
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
    /// `"life_fragment"` (V1) or `"repeat"`; rows written before push modes
    /// decode as `"life_fragment"`.
    public var mode: String
    /// Repeat pushes only: the theme's id and name (never its members).
    public var themeId: String?
    public var themeName: String?
    /// Repeat pushes only: what each judge call cost.
    public var roundUsages: [RoundUsage]?
    /// Repeat pushes only: why round 2 tries failed.
    public var roundTwoTries: [String]?

    public init(pushId: String, isDebug: Bool = false, belongsTo: String, groupKey: String, photoIds: [String],
                bucket: PushBucket, place: String?, score: FragmentScore, body: String, question: String,
                questionType: String, scheduledFor: Date) {
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
        self.question = question
        self.questionType = questionType
        self.scheduledFor = scheduledFor
        self.notOpened = false
        self.mode = "life_fragment"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        pushId = try box.decode(String.self, forKey: .pushId)
        identifier = try box.decode(String.self, forKey: .identifier)
        isDebug = try box.decode(Bool.self, forKey: .isDebug)
        belongsTo = try box.decode(String.self, forKey: .belongsTo)
        groupKey = try box.decode(String.self, forKey: .groupKey)
        photoIds = try box.decode([String].self, forKey: .photoIds)
        bucket = try box.decode(PushBucket.self, forKey: .bucket)
        place = try box.decodeIfPresent(String.self, forKey: .place)
        score = try box.decode(FragmentScore.self, forKey: .score)
        body = try box.decode(String.self, forKey: .body)
        question = try box.decodeIfPresent(String.self, forKey: .question)
        questionType = try box.decodeIfPresent(String.self, forKey: .questionType)
        scheduledFor = try box.decode(Date.self, forKey: .scheduledFor)
        deliveredAt = try box.decodeIfPresent(Date.self, forKey: .deliveredAt)
        notDeliveredReason = try box.decodeIfPresent(String.self, forKey: .notDeliveredReason)
        openedAt = try box.decodeIfPresent(Date.self, forKey: .openedAt)
        storyFinishedAt = try box.decodeIfPresent(Date.self, forKey: .storyFinishedAt)
        madePageAt = try box.decodeIfPresent(Date.self, forKey: .madePageAt)
        // A newer build's choice loses only the choice, not the row.
        menuAction = (try? box.decodeIfPresent(MenuAction.self, forKey: .menuAction)) ?? nil
        menuActionAt = try box.decodeIfPresent(Date.self, forKey: .menuActionAt)
        removedReason = try box.decodeIfPresent(RemovalReason.self, forKey: .removedReason)
        removedAt = try box.decodeIfPresent(Date.self, forKey: .removedAt)
        notOpened = try box.decode(Bool.self, forKey: .notOpened)
        mode = try box.decodeIfPresent(String.self, forKey: .mode) ?? "life_fragment"
        themeId = try box.decodeIfPresent(String.self, forKey: .themeId)
        themeName = try box.decodeIfPresent(String.self, forKey: .themeName)
        roundUsages = try box.decodeIfPresent([RoundUsage].self, forKey: .roundUsages)
        roundTwoTries = try box.decodeIfPresent([String].self, forKey: .roundTwoTries)
    }

    /// Scheduled and still waiting: not removed, not delivered, not dropped
    /// by iOS (`notDeliveredReason`), not a debug push. Only an active push
    /// holds its group and belongs-to day.
    public var isActive: Bool {
        removedAt == nil && removedReason == nil && deliveredAt == nil && notDeliveredReason == nil && !isDebug
    }
}

/// The ledger as one JSON file (an array of entries) under Application
/// Support. A missing file loads as empty. A row that does not decode is
/// skipped; a file that does not parse, or has such rows, is first moved
/// aside (`PhotoTriggerPaths.setAside`), so no save writes over the history.
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
        guard let data = try? Data(contentsOf: file) else { return [] }
        guard let rows = try? TriggerMemory.decoder.decode([Lenient<LedgerEntry>].self, from: data) else {
            PhotoTriggerPaths.setAside(file)
            return []
        }
        let entries = rows.compactMap(\.value)
        if entries.count < rows.count {
            // The rows that could be read are the ledger from now on.
            PhotoTriggerPaths.setAside(file)
            try? save(entries)
        }
        return entries
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

    /// Deletes the file (back to empty).
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
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
            // A recorded reason is terminal: iOS dropped the push at fire time.
            if entry.deliveredAt == nil, entry.notDeliveredReason == nil, entry.scheduledFor <= now,
               !pending.contains(entry.identifier) {
                if notificationsAllowed {
                    entry.deliveredAt = entry.scheduledFor
                } else {
                    entry.notDeliveredReason = "notificationsOff"
                }
            }
            if let delivered = entry.deliveredAt, entry.openedAt == nil,
               !entry.notOpened, now.timeIntervalSince(delivered) >= openWindow {
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

    /// The photos of delivered, non-debug pushes: a group holding one was
    /// pushed, whatever day a time-zone change now puts it on.
    public static func pushedPhotos(_ entries: [LedgerEntry]) -> Set<String> {
        Set(entries.filter { $0.deliveredAt != nil && !$0.isDebug }.flatMap(\.photoIds))
    }
}
