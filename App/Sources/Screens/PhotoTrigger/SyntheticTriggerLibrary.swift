#if DEBUG
import MiraNoteKit
import UIKit

/// `-UITEST-TRIGGER`: a made-up library of painted colour blocks with
/// chosen dates -- no personal photos, no PhotoKit, no permission prompt.
/// Three fragments: A (10 photos, 3 days ago, afternoon) ranks first, B (6,
/// 5 days ago, morning) second, C (3, 8 days ago, evening) third.
///
/// Switches: `-TRIGGER-EMPTY` (no photos), `-TRIGGER-PHOTOS-DENIED`,
/// `-PHOTOS-LIMITED`, `-TRIGGER-MISSING <n>` (the first n photos of any
/// record are gone), `-TRIGGER-MANY-GROUPS` (five more fragments D-H, eight
/// in all: one more than the seven nights) and `-TRIGGER-OTHER-ONLY` (only
/// D, whose photos are art: the `other` bucket). For the story:
/// `-TRIGGER-SLOW-PHOTOS <s>` (each photo takes that long to arrive) and
/// `-TRIGGER-UNREADABLE <n>` (the first n photos of a group never arrive).
struct SyntheticTriggerLibrary: PhotoLibraryReading, TriggerPhotoProviding, PhotoAnalyzing {
    struct Group {
        let name: String
        let count: Int
        let daysAgo: Int
        let hour: Int
        let broad: Set<BroadCategory>
        let hue: CGFloat
    }

    static let groups = [
        Group(name: "A", count: 10, daysAgo: 3, hour: 14, broad: [.food_drink, .tableware], hue: 0.08),
        Group(name: "B", count: 6, daysAgo: 5, hour: 9, broad: [.sky, .plant], hue: 0.55),
        Group(name: "C", count: 3, daysAgo: 8, hour: 19, broad: [.event], hue: 0.8)
    ]

    /// D is `other`; D-H only with `-TRIGGER-MANY-GROUPS` / `-TRIGGER-OTHER-ONLY`.
    private static let extraGroups = [
        Group(name: "D", count: 5, daysAgo: 4, hour: 15, broad: [.art], hue: 0.95),
        Group(name: "E", count: 6, daysAgo: 2, hour: 11, broad: [.animal], hue: 0.3),
        Group(name: "F", count: 5, daysAgo: 6, hour: 16, broad: [.built], hue: 0.62),
        Group(name: "G", count: 5, daysAgo: 7, hour: 13, broad: [.interior], hue: 0.12),
        Group(name: "H", count: 6, daysAgo: 9, hour: 10, broad: [.water], hue: 0.5)
    ]

    private static let everyGroup = groups + extraGroups

    /// The groups this launch's library holds.
    private var active: [Group] {
        if arguments.contains("-TRIGGER-OTHER-ONLY") { return Array(Self.extraGroups.prefix(1)) }
        return arguments.contains("-TRIGGER-MANY-GROUPS") ? Self.everyGroup : Self.groups
    }

    private let arguments = ProcessInfo.processInfo.arguments
    private let now: Date
    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    private var missingCount: Int {
        guard let index = arguments.firstIndex(of: "-TRIGGER-MISSING"), arguments.indices.contains(index + 1)
        else { return 0 }
        return Int(arguments[index + 1]) ?? 0
    }

    var all: [LibraryAsset] {
        guard !arguments.contains("-TRIGGER-EMPTY") else { return [] }
        return active.flatMap { group -> [LibraryAsset] in
            let day = calendar.date(byAdding: .day, value: -group.daysAgo, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(bySettingHour: group.hour, minute: 0, second: 0, of: day) ?? day
            return (0..<group.count).map { index in
                LibraryAsset(id: "synthetic-\(group.name)-\(index)",
                             takenAt: start.addingTimeInterval(Double(index) * 1500),
                             location: nil, isFavorite: false, isEdited: false, isScreenshot: false, isHidden: false,
                             isVideo: false, originalFilename: "IMG_\(group.name)\(index).HEIC", burstId: nil)
            }
        }
    }

    func requestAccess() async -> PhotoAccess {
        if arguments.contains("-TRIGGER-PHOTOS-DENIED") { return .denied }
        return arguments.contains("-PHOTOS-LIMITED") ? .limited : .full
    }

    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset] {
        all.filter { ($0.takenAt ?? .distantPast) >= date }
    }

    func uploadData(for id: String) async -> Data? {
        Self.paint(id, side: 600).jpegData(compressionQuality: 0.8)
    }

    func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
        guard id.hasPrefix("synthetic-"), Self.order(id) >= number(after: "-TRIGGER-UNREADABLE") else { return nil }
        let delay = number(after: "-TRIGGER-SLOW-PHOTOS")
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        return Self.paint(id, side: min(maxPixel, 900))
    }

    /// The whole number after `flag` in the launch arguments; 0 without one.
    private func number(after flag: String) -> Int {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return 0 }
        return Int(arguments[index + 1]) ?? 0
    }

    func existing(_ ids: [String]) async -> Set<String> {
        Set(ids.sorted { Self.order($0) < Self.order($1) }.dropFirst(missingCount))
    }

    /// A photo's place in its group, for "the first n are gone".
    private static func order(_ id: String) -> Int {
        Int(id.split(separator: "-").last ?? "") ?? 0
    }

    // MARK: Analysis

    func analyze(_ id: String) async -> PhotoAnalysis? {
        let parts = id.split(separator: "-")
        guard parts.count == 3, let group = Self.everyGroup.first(where: { $0.name == parts[1] }) else { return nil }
        // Photo 5 of each group is the best: the fake AI's peak.
        let best = parts[2] == "5" || (group.count <= 5 && parts[2] == "1")
        return PhotoAnalysis(id: id, labels: [], broad: group.broad, faces: 0, aesthetics: best ? 0.9 : nil,
                             isUtility: false, featurePrint: nil)
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? { nil }

    /// A colour block with the photo's number, portrait on even numbers.
    static func paint(_ id: String, side: CGFloat) -> UIImage {
        let parts = id.split(separator: "-")
        let group = everyGroup.first { parts.count == 3 && $0.name == parts[1] } ?? groups[0]
        let index = order(id)
        let size = index.isMultiple(of: 2)
            ? CGSize(width: side * 0.75, height: side) : CGSize(width: side, height: side * 0.75)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(hue: group.hue, saturation: 0.35 + 0.05 * CGFloat(index % 5),
                    brightness: 0.95 - 0.06 * CGFloat(index % 6), alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "\(group.name)\(index)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.25, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                      withAttributes: attributes)
        }
    }
}

/// `-UITEST-TRIGGER` with the fake AI off: a backend that answers at once
/// with a memory that has a detail line and three candidate questions, the
/// copy_v2 shape. `-TRIGGER-BACKEND-DOWN` cannot be reached;
/// `-TRIGGER-REJECT` turns every group down; `-TRIGGER-SLOW-AI <s>` keeps
/// each job running for that many seconds; `-TRIGGER-DETAIL <words>` is the
/// detail line and push body (screenshots of a long line).
struct UITestComposeClient: ComposeClient {
    private let arguments = ProcessInfo.processInfo.arguments

    /// Every group gets the same three: nights side by side take turns
    /// (zoom, order, found, zoom...), which shows the picker at work.
    private static let questions = [
        TriggerMemory.Ending.Question(text: "What was on the table?", type: "zoom", source: "llm"),
        TriggerMemory.Ending.Question(text: "Which dish went first?", type: "order", source: "llm"),
        TriggerMemory.Ending.Question(text: "How did you find the place?", type: "found", source: "llm")
    ]

    private var detail: String {
        guard let index = arguments.firstIndex(of: "-TRIGGER-DETAIL"), arguments.indices.contains(index + 1)
        else { return "A quiet light on the table" }
        return arguments[index + 1]
    }

    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        if arguments.contains("-TRIGGER-BACKEND-DOWN") { throw ComposeError.unreachable }
        let data = try JSONEncoder().encode(meta)
        // The job id carries the meta and when it was submitted.
        return "\(Int(Date().timeIntervalSince1970))|" + data.base64EncodedString()
    }

    private var slowSeconds: Double {
        guard let index = arguments.firstIndex(of: "-TRIGGER-SLOW-AI"), arguments.indices.contains(index + 1)
        else { return 0 }
        return Double(arguments[index + 1]) ?? 0
    }

    func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus] {
        var result: [String: ComposeJobStatus] = [:]
        for id in jobIds { result[id] = try await poll(id) }
        return result
    }

    func poll(_ jobId: String) async throws -> ComposeJobStatus {
        let parts = jobId.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let submitted = Double(parts[0]), let data = Data(base64Encoded: parts[1]),
              let meta = try? JSONDecoder().decode(ComposeMeta.self, from: data) else { return .expired }
        if Date().timeIntervalSince1970 - submitted < slowSeconds { return .running }
        if arguments.contains("-TRIGGER-REJECT") {
            return .rejected(reason: "too_few_selected", message: "Too few photos for \(meta.date)")
        }
        let iso = ISO8601DateFormatter()
        let chosen = Array(meta.photos.prefix(8))
        let peak = chosen.count > 1 ? chosen[1].id : chosen.first?.id ?? ""
        let photos = chosen.map {
            TriggerMemory.Photo(id: $0.id, takenAt: iso.date(from: $0.takenAt) ?? .now, isPeak: $0.id == peak)
        }
        let fact = TriggerWords.factLine(day: meta.date, place: meta.place)
        return .ok(TriggerMemory(
            id: meta.groupKey, date: meta.date, daypart: .afternoon, bucket: "Food and drink",
            push: .init(title: fact + TriggerWords.separator + "afternoon", body: detail, coverPhotoId: peak),
            story: .init(firstFrameLabel: fact, photos: photos),
            ending: .init(factLine: fact, detail: detail, questions: Self.questions, ctaLabel: "Keep this afternoon"),
            facts: Dictionary(uniqueKeysWithValues: chosen.map {
                ($0.id, "Subject: a painted block; description: block \($0.id); people: 0")
            }),
            generation: .init(bodySource: "llm", questionSource: "llm", model: "uitest", costCny: 0, latencyMs: 0)
        ))
    }
}

/// `-UITEST-TRIGGER`: notifications that are on (`-TRIGGER-NOTIFICATIONS-OFF`
/// turns them off) and never reach the real notification centre.
final class UITestNotifier: PushNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: Set<String> = []

    func requestPermission() async -> Bool {
        !ProcessInfo.processInfo.arguments.contains("-TRIGGER-NOTIFICATIONS-OFF")
    }

    func isAllowed() async -> Bool { await requestPermission() }
    func pending() async -> Set<String> { lock.withLock { scheduled } }
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        // A debug push (no slot) fires in 10 s and is not kept.
        if at != nil { lock.withLock { _ = scheduled.insert(identifier) } }
        return true
    }
    func removePending(_ identifiers: [String]) async { lock.withLock { scheduled.subtract(identifiers) } }
    func removeDelivered(_ identifiers: [String]) async {}
}

struct UITestPlaces: PlaceNaming {
    func name(for point: GeoPoint) async -> String? { nil }
}
#endif
