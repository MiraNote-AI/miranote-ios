import Foundation

/// Qwen's round-2 answer (prompt draft, round 2 "expected answer"): per
/// numbered candidate whether it belongs, which one it duplicates, whether
/// it is poor or sensitive; and the listed names the theme is the same as
/// or much like.
public struct RoundTwoAnswer: Decodable, Equatable, Sendable {
    public struct Photo: Decodable, Equatable, Sendable {
        /// The candidate's number (`RoundTwoRequest.Photo.n`).
        public let id: Int
        /// Unsaid: not belonging, so not kept.
        public let belongs: Bool
        public let dupOf: Int?
        public let poor: Bool
        public let sensitive: Bool

        public init(id: Int, belongs: Bool, dupOf: Int?, poor: Bool, sensitive: Bool) {
            self.id = id
            self.belongs = belongs
            self.dupOf = dupOf
            self.poor = poor
            self.sensitive = sensitive
        }

        private enum CodingKeys: String, CodingKey {
            case id, belongs, poor, sensitive
            case dupOf = "dup_of"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            belongs = try container.decodeIfPresent(Bool.self, forKey: .belongs) ?? false
            dupOf = try container.decodeIfPresent(Int.self, forKey: .dupOf)
            poor = try container.decodeIfPresent(Bool.self, forKey: .poor) ?? false
            sensitive = try container.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        }
    }

    /// A compared name Qwen found the same or much like the theme.
    public struct Similar: Decodable, Equatable, Sendable {
        public let name: String
        /// As Qwen wrote it (Chinese: the same kind, or much like).
        public let level: String

        public init(name: String, level: String) {
            self.name = name
            self.level = level
        }

        private enum CodingKeys: String, CodingKey {
            case name, level
        }

        /// A name without a level still counts.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
        }
    }

    /// Entries without a number are left out.
    public let photos: [Photo]
    /// Blank names are left out.
    public let similarTo: [Similar]

    private enum CodingKeys: String, CodingKey {
        case photos
        case similarTo = "similar_to"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photos = try container.decode([Lenient<Photo>].self, forKey: .photos).compactMap(\.value)
        similarTo = (try container.decodeIfPresent([Lenient<Similar>].self, forKey: .similarTo) ?? [])
            .compactMap(\.value)
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The first JSON object in `text`; nil without one that has `photos`.
    public static func parse(_ text: String) -> RoundTwoAnswer? {
        guard let object = RoundOneAnswer.firstObject(in: text) else { return nil }
        return try? JSONDecoder().decode(RoundTwoAnswer.self, from: Data(object.utf8))
    }
}

/// What the phone does with a round-2 answer (spec 6.13, prompt draft
/// "after the phone gets the answer"), and the names it compares with.
public enum RoundTwo {
    /// A theme is pushed only with photos of this many days (S10).
    public static let minDays = 5
    /// Repeat themes pushed this many days back are compared with (F3).
    static let pushedDays = 60

    /// The candidates left after the answer, by number: those that do not
    /// belong (or that the answer skips), are poor or sensitive go; of a
    /// duplicate pair the one with the lower aesthetics goes (a tie: the
    /// one marked the duplicate). `days` counts the local days left.
    /// - Parameters:
    ///   - candidates: number -> photo id, as sent.
    ///   - aesthetics: photo id -> aesthetics (missing: 0.5, as iOS 17).
    ///   - days: photo id -> its local `yyyy-MM-dd`.
    public static func survivors(_ answer: RoundTwoAnswer, candidates: [Int: String], aesthetics: [String: Double],
                                 days: [String: String]) -> (photos: [String], days: Int) {
        var judged: [Int: RoundTwoAnswer.Photo] = [:]
        for photo in answer.photos where candidates[photo.id] != nil && judged[photo.id] == nil {
            judged[photo.id] = photo
        }
        var kept = Set(judged.values.filter { $0.belongs && !$0.poor && !$0.sensitive }.map(\.id))
        func score(_ number: Int) -> Double { candidates[number].flatMap { aesthetics[$0] } ?? 0.5 }
        for number in judged.keys.sorted() {
            guard let other = judged[number]?.dupOf, other != number, kept.contains(number),
                  kept.contains(other) else { continue }
            kept.remove(score(other) >= score(number) ? number : other)
        }
        let photos = kept.sorted().compactMap { candidates[$0] }
        return (photos, Set(photos.compactMap { days[$0] }).count)
    }

    /// Round 2's two compare lists (spec 6.13, F7): `pushed` = the names of
    /// other themes' repeat pushes that stand (not debug, not taken back)
    /// and are due from 60 days before `now` on; `blocked` = every blocked
    /// theme's name, however old. Blank names are left out, each name goes
    /// once, cut to the backend's limits (20 and 50, names up to 60 long).
    public static func comparisonLists(ledger: [LedgerEntry], rows: [ThemeRow], themeId: String, now: Date,
                                       calendar: Calendar) -> (pushed: [String], blocked: [String]) {
        let since = calendar.date(byAdding: .day, value: -pushedDays, to: now) ?? now
        let pushed = ledger.filter {
            $0.mode == RepeatComposeMeta.mode && !$0.isDebug && $0.removedAt == nil && $0.removedReason == nil
                && $0.themeId != themeId && $0.scheduledFor >= since
        }.compactMap(\.themeName)
        let blocked = rows.filter { $0.status == .blocked }.map(\.name)
        return (Array(names(pushed).prefix(RoundTwoRequest.maxPushed)),
                Array(names(blocked).prefix(RoundTwoRequest.maxBlocked)))
    }

    /// The backend's longest compare name.
    static let maxNameCharacters = 60

    private static func names(_ all: [String]) -> [String] {
        var seen = Set<String>()
        return all.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= maxNameCharacters
                && seen.insert($0).inserted
        }
    }
}

/// Why a round-2 try gave no answer to use.
enum RoundTwoFailure: Error, Equatable {
    /// None of the candidates could be read.
    case unreadableImages
    case call(ThemeRoundError)
    case notJSON

    var text: String {
        switch self {
        case .unreadableImages: return "no photo could be read for round 2"
        case .call(let error): return "round 2 call failed (\(ThemeEngine.AskFailure.describe(error)))"
        case .notJSON: return "round 2 answer not used (\(RoundOneProblem.notJSON.rawValue))"
        }
    }
}

/// One round-2 call: the numbering sent, its answer, what it cost.
struct RoundTwoCall: Sendable {
    /// Number -> photo id, as sent.
    var numbering: [Int: String]
    var result: Result<RoundTwoAnswer, RoundTwoFailure>
    var usage: RoundUsage?
}

extension ThemeEngine {
    /// Asks round 2 about `theme` (a test push asks afresh: no stored
    /// answer is reused). The candidates that can be read are numbered from
    /// 1 in the order given, as 336 px images with no metadata; the reply
    /// goes in the round log, with `notJSON` when it is not an answer.
    /// `facts` (by photo id) say when and where a photo was taken.
    func roundTwo(theme: RoundTwoRequest.Theme, candidates: [String], pushed: [String], blocked: [String],
                  themeId: String, facts: [String: RoundTwoRequest.PhotoFacts] = [:]) async -> RoundTwoCall {
        var numbering: [Int: String] = [:]
        var images: [(n: Int, jpeg: Data)] = []
        for id in candidates {
            guard let data = await deps.imageData(id),
                  let jpeg = UploadImage.prepare(data, maxPixel: Self.imagePixels) else { continue }
            let number = images.count + 1
            numbering[number] = id
            images.append((number, jpeg))
        }
        guard !images.isEmpty else {
            return RoundTwoCall(numbering: [:], result: .failure(.unreadableImages), usage: nil)
        }
        let photos = images.map { RoundTwoRequest.Photo(n: $0.n, facts: numbering[$0.n].flatMap { facts[$0] }) }
        let request = RoundTwoRequest(theme: theme, photos: photos, pushed: pushed, blocked: blocked)
        let reply: RoundReply
        do {
            reply = try await deps.client.roundTwo(request, images: images)
        } catch {
            let failure = error as? ThemeRoundError ?? .unreachable
            var usage: RoundUsage?
            if case .model(_, let spent) = failure { usage = spent }
            return RoundTwoCall(numbering: numbering, result: .failure(.call(failure)), usage: usage)
        }
        let answer = RoundTwoAnswer.parse(reply.reply)
        try? deps.rounds.append(RoundLogEntry(at: deps.now(), kind: "round2", themeId: themeId,
                                              key: "round2-" + UUID().uuidString, reply: reply.reply,
                                              usage: reply.usage, problem: answer == nil ? .notJSON : nil,
                                              where: [:]))
        return RoundTwoCall(numbering: numbering, result: answer.map { .success($0) } ?? .failure(.notJSON),
                            usage: reply.usage)
    }
}
