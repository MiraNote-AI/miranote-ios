import Foundation

// MARK: - What a run needs from the app

public enum PhotoAccess: Equatable, Sendable {
    case full, limited, denied
}

/// PhotoKit, as far as a run needs it.
public protocol PhotoLibraryReading: Sendable {
    /// Asks the first time; limited access is access.
    func requestAccess() async -> PhotoAccess
    /// Image assets taken at or after `date`: metadata only, no pixels.
    /// `knownFilenames` (localIdentifier -> original file name, kept from
    /// earlier analyses) spares asking PhotoKit for those names again.
    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset]
    /// The photo's bytes for upload (any size from about 1000 px), or nil.
    func uploadData(for id: String) async -> Data?
}

/// On-device Vision.
public protocol PhotoAnalyzing: Sendable {
    /// Nil when the photo cannot be read: it sits the run out and is tried
    /// again a day later (`TriggerRanking.retryAfter`).
    func analyze(_ id: String) async -> PhotoAnalysis?
    /// FeaturePrint distance between two photos' archived prints (the ids
    /// let an implementation keep the unarchived prints by photo).
    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float?
}

/// Apple's reverse geocoder.
public protocol PlaceNaming: Sendable {
    /// Nil when there is no place to name there; throws when the lookup
    /// itself failed (no network, throttled), so a caller can try later
    /// instead of taking it for "no place".
    func name(for point: GeoPoint) async throws -> String?
}

/// Local notifications. Every identifier this feature adds starts with
/// `PushIdentifier.prefix`; removals never touch anyone else's.
public protocol PushNotificationCenter: Sendable {
    func isAllowed() async -> Bool
    /// Asks the first time; false when notifications are off.
    func requestPermission() async -> Bool
    /// Identifiers of every pending request (ours and others').
    func pending() async -> Set<String>
    /// Schedules the push for `record` (saved already) at the local
    /// date/time `at`, or 10 s out when nil; false when it was not added.
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool
    func removePending(_ identifiers: [String]) async
    func removeDelivered(_ identifiers: [String]) async
}

/// The notification identifiers this feature owns.
public enum PushIdentifier {
    public static let prefix = "pt."

    public static func make(_ pushId: String) -> String { prefix + pushId }

    public static func isOurs(_ identifier: String) -> Bool { identifier.hasPrefix(prefix) }
}

// MARK: - Progress

public enum TriggerFailure: Equatable, Sendable {
    case backendUnreachable
    case aiTimeout
    case noFragment
    case notificationsOff
    case photosDenied
    /// 401: this build has no valid beta token.
    case unauthorized
    /// Any other refusal or error, with the backend's message.
    case backend(String)
}

/// What the debug entry shows under its buttons (handoff 7.5), in order.
public enum TriggerProgress: Equatable, Sendable {
    case preparing
    /// Only part of the library is shared: a note, the run goes on.
    case partialLibrary
    case analyzing(done: Int, total: Int)
    /// "M.DD" date, the place when known, unique photos in the group.
    case askingAI(rank: Int, date: String, place: String?, count: Int)
    /// "Push next" ran past the last group and starts from the top.
    case wrapped
    case rejected(rank: Int, message: String, next: Int)
    case scheduled(rank: Int, score: Double)
    /// Every group tried this press was turned down: three, or all there
    /// were when fewer.
    case allFailed(tried: Int)
    case failed(TriggerFailure)
}

/// A pushable fragment and its place in the ranking.
public struct RankedGroup: Equatable, Sendable {
    /// 1-based.
    public let rank: Int
    public let fragment: Fragment
    public let score: FragmentScore
}

/// Everything a run talks to, injectable for tests.
public struct TriggerDependencies: Sendable {
    public var library: PhotoLibraryReading
    public var analyzer: PhotoAnalyzing
    public var places: PlaceNaming
    public var client: ComposeClient
    public var notifier: PushNotificationCenter
    public var analyses: AnalysisStore
    public var records: PushRecordStore
    public var calendar: Calendar
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) async throws -> Void
    /// The fake-AI switch, read at each press.
    public var fakeAI: @Sendable () -> Bool
    /// zh-Hans catalog lookup for content (`TriggerContentKey`).
    public var zh: @Sendable (String) -> String
    /// Receives each press's grouping as JSON (`GroupingReport`); nil keeps none.
    public var groupingReport: (@Sendable (Data) -> Void)?

    public init(
        library: PhotoLibraryReading, analyzer: PhotoAnalyzing, places: PlaceNaming, client: ComposeClient,
        notifier: PushNotificationCenter, analyses: AnalysisStore, records: PushRecordStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        fakeAI: @escaping @Sendable () -> Bool, zh: @escaping @Sendable (String) -> String,
        groupingReport: (@Sendable (Data) -> Void)? = nil
    ) {
        self.library = library
        self.analyzer = analyzer
        self.places = places
        self.client = client
        self.notifier = notifier
        self.analyses = analyses
        self.records = records
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
        self.fakeAI = fakeAI
        self.zh = zh
        self.groupingReport = groupingReport
    }
}
