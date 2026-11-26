import Foundation

/// The meta of the backend's round-1 call (`POST /collections/rounds/1`):
/// what the phone tells Qwen about one pile. Group entries carry only
/// `{id, days, where}`; `SplitGroup` itself (it holds the place center) is
/// never encoded.
public struct RoundOneRequest: Encodable, Equatable, Sendable {
    /// A group as the backend wants it.
    public struct Group: Encodable, Equatable, Sendable {
        public let id: String
        public let days: Int
        public let `where`: WhereFacts
        /// The label shares of a content (A) group; nil, and no key, for B.
        public let tags: [RoundOneRequest.Tag]?

        private enum CodingKeys: String, CodingKey {
            case id, days, `where`, tags
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(days, forKey: .days)
            try container.encode(`where`, forKey: .where)
            try container.encodeIfPresent(tags, forKey: .tags)
        }
    }

    /// One label: its share of the group (`in`) and of the rest of the pile (`out`).
    public struct Tag: Encodable, Equatable, Sendable {
        public let label: String
        public let inside: Double
        public let outside: Double

        private enum CodingKeys: String, CodingKey {
            case label
            case inside = "in"
            case outside = "out"
        }
    }

    /// One image: its number (1...N, the name of its upload part), its group
    /// in each split, and the labels the phone recognised in it.
    public struct Photo: Encodable, Equatable, Sendable {
        // swiftlint:disable identifier_name
        public let n: Int
        public let a: String
        public let b: String
        // swiftlint:enable identifier_name
        public let labels: [String]
    }

    /// The names from the last time (re-ask, spec 6.5).
    public struct Old: Encodable, Equatable, Sendable {
        public let pileName: String
        public let groups: [String]

        public init(pileName: String, groups: [String]) {
            self.pileName = pileName
            self.groups = groups
        }

        private enum CodingKeys: String, CodingKey {
            case pileName = "pile_name"
            case groups
        }
    }

    /// At most this many labels per photo.
    static let maxLabels = 8

    public let photoCount: Int
    public let dayCount: Int
    public let splitA: [Group]
    public let splitB: [Group]
    public let photos: [Photo]
    public let old: Old?
    /// Image number -> library photo id, to upload `n.jpg`. Not encoded.
    public let photoIds: [Int: String]

    private enum CodingKeys: String, CodingKey {
        case pile
        case splitA = "split_a"
        case splitB = "split_b"
        case photos
        case old
    }

    private enum PileKeys: String, CodingKey {
        case photoCount = "photo_count"
        case dayCount = "day_count"
    }

    // Builds the request for `photos`, numbered 1... in the given order.
    // swiftlint:disable:next identifier_name function_parameter_count
    static func make(pile: Pile, moments: [String: Moment], a: [SplitGroup], b: [SplitGroup],
                     photos: [SampledPhoto], old: Old?) -> RoundOneRequest {
        func entries(_ groups: [SplitGroup], withTags: Bool) -> [Group] {
            groups.map { group in
                let tags = withTags
                    ? PileSplits.tagShares(of: group.momentIds, pile: pile, moments: moments)
                        .map { Tag(label: $0.label, inside: $0.inside, outside: $0.outside) }
                    : nil
                return Group(id: group.id, days: group.days, where: group.where, tags: tags)
            }
        }
        var ids: [Int: String] = [:]
        let rows = photos.enumerated().map { offset, photo -> Photo in
            ids[offset + 1] = photo.photoId
            let present = (moments[photo.momentId]?.labels ?? [])
                .filter { $0.confidence >= PileSplits.presentConfidence }
                .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.id < $1.id }
                .prefix(maxLabels).map(\.id)
            return Photo(n: offset + 1, a: photo.a, b: photo.b, labels: Array(present))
        }
        // Photos, not moments: the prompt says "N photos on D different days".
        let photoCount = pile.momentIds.reduce(0) { $0 + (moments[$1]?.photoIds.count ?? 1) }
        return RoundOneRequest(photoCount: photoCount, dayCount: pile.days, splitA: entries(a, withTags: true),
                               splitB: entries(b, withTags: false), photos: rows, old: old, photoIds: ids)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var pile = container.nestedContainer(keyedBy: PileKeys.self, forKey: .pile)
        try pile.encode(photoCount, forKey: .photoCount)
        try pile.encode(dayCount, forKey: .dayCount)
        try container.encode(splitA, forKey: .splitA)
        try container.encode(splitB, forKey: .splitB)
        try container.encode(photos, forKey: .photos)
        try container.encode(old, forKey: .old)  // null when nil: the backend wants the key
    }
}

/// What Qwen answers in round 1 (the "expected answer" of the prompt draft).
/// Decoding is lenient: a missing array is empty, a missing string nil or empty.
public struct RoundOneAnswer: Decodable, Equatable, Sendable {
    public struct Group: Decodable, Equatable, Sendable {
        /// Offered group ids, one or more (several = merged).
        public var from: [String]
        public var name: String
        public var noun: String?
        public var samePart: String?
        /// Evidence labels; only meaningful for split A.
        public var evidence: [String]

        private enum CodingKeys: String, CodingKey {
            case from, name, noun, evidence
            case samePart = "same_part"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = container.lenientStrings(.from)
            name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
            noun = try? container.decodeIfPresent(String.self, forKey: .noun)
            samePart = try? container.decodeIfPresent(String.self, forKey: .samePart)
            evidence = container.lenientStrings(.evidence)
        }
    }

    public var sensitive: Bool
    public var pileName: String?
    public var pileNoun: String?
    /// `A`, `B` or `none` (also when missing).
    public var chosen: String
    public var groups: [Group]
    public var dropGroups: [String]
    /// Image numbers that do not belong to the pile.
    public var notInPile: [Int]
    public var twoKinds: Bool

    private enum CodingKeys: String, CodingKey {
        case sensitive, chosen, groups
        case pileName = "pile_name"
        case pileNoun = "pile_noun"
        case dropGroups = "drop_groups"
        case notInPile = "not_in_pile"
        case twoKinds = "two_kinds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sensitive = (try? container.decodeIfPresent(Bool.self, forKey: .sensitive)) ?? false
        pileName = try? container.decodeIfPresent(String.self, forKey: .pileName)
        pileNoun = try? container.decodeIfPresent(String.self, forKey: .pileNoun)
        let raw = ((try? container.decodeIfPresent(String.self, forKey: .chosen)) ?? "")
            .trimmingCharacters(in: .whitespaces)
        chosen = raw.uppercased() == "A" || raw.uppercased() == "B" ? raw.uppercased() : raw.isEmpty ? "none" : raw
        groups = (try? container.decodeIfPresent([Lossy<Group>].self, forKey: .groups))?.compactMap(\.value) ?? []
        dropGroups = container.lenientStrings(.dropGroups)
        notInPile = (try? container.decodeIfPresent([Int].self, forKey: .notInPile)) ?? []
        twoKinds = (try? container.decodeIfPresent(Bool.self, forKey: .twoKinds)) ?? false
    }

    /// Decodes Qwen's reply: the first top-level JSON object in `text`
    /// (it may sit in a ```json fence or have words around it).
    public static func parse(_ text: String) -> Result<RoundOneAnswer, RoundOneProblem> {
        guard let object = firstObject(in: text),
              let answer = try? JSONDecoder().decode(RoundOneAnswer.self, from: Data(object.utf8)) else {
            return .failure(.notJSON)
        }
        return .success(answer)
    }

    // swiftlint:disable cyclomatic_complexity
    /// The text of the first balanced `{...}`, braces inside strings ignored.
    static func firstObject(in text: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"" where depth > 0: inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}" where depth > 0:
                depth -= 1
                if depth == 0, let start { return String(text[start...index]) }
            default: break
            }
        }
        return nil
    }
    // swiftlint:enable cyclomatic_complexity
}

/// Decodes to nil instead of failing, so one bad row does not lose the answer.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

private extension KeyedDecodingContainer {
    /// A string array; numbers become their text; anything else is dropped.
    func lenientStrings(_ key: Key) -> [String] {
        if let strings = try? decodeIfPresent([String].self, forKey: key) { return strings }
        if let numbers = try? decodeIfPresent([Int].self, forKey: key) { return numbers.map(String.init) }
        return []
    }
}

/// Why a round-1 answer was not used.
public enum RoundOneProblem: String, Codable, Error, Sendable {
    case notJSON
    case unknownGroup
    case groupFromOtherSplit
    case imageNumberInFrom
    case groupUsedTwice
    case tooLong
    /// Not sensitive, yet no `pile_name`.
    case blankPileName
}

/// One name to shorten (the backend shorten body's `items`).
public struct ShortenItem: Codable, Equatable, Sendable {
    /// `pile`, or the group's first `from` id.
    public let key: String
    public let name: String
    public let samePart: String

    public init(key: String, name: String, samePart: String) {
        self.key = key
        self.name = name
        self.samePart = samePart
    }

    private enum CodingKeys: String, CodingKey {
        case key, name
        case samePart = "same_part"
    }
}

/// The phone's checks of a round-1 answer (prompt draft, "after the first answer").
enum RoundOneValidator {
    static let maxNameCharacters = 10
    static let maxSamePartCharacters = 20

    /// The answer ready to use, or why it is not.
    /// - A sensitive answer is returned as is (no groups or name are expected).
    /// - `chosen == "none"`: no groups are expected, so any groups (and drops) are ignored.
    /// - A group with no `from` or a blank name is `.unknownGroup`.
    /// - With `chosen == "B"` the evidence is emptied; unknown `dropGroups` are removed.
    /// - Groups that pass, but no `pile_name`, is `.blankPileName`.
    static func validate(_ answer: RoundOneAnswer,
                         offered: (a: [SplitGroup], b: [SplitGroup])) -> Result<RoundOneAnswer, RoundOneProblem> {
        if answer.sensitive { return .success(answer) }
        return checkedGroups(answer, offered: offered).flatMap { valid in
            let name = valid.pileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? .failure(.blankPileName) : .success(valid)
        }
    }

    // swiftlint:disable cyclomatic_complexity
    private static func checkedGroups(_ answer: RoundOneAnswer, offered: (a: [SplitGroup], b: [SplitGroup]))
        -> Result<RoundOneAnswer, RoundOneProblem> {
        var result = answer
        let own: Set<String>
        let other: Set<String>
        switch answer.chosen {
        case "A":
            own = Set(offered.a.map(\.id))
            other = Set(offered.b.map(\.id))
        case "B":
            own = Set(offered.b.map(\.id))
            other = Set(offered.a.map(\.id))
        case "none":
            result.groups = []
            result.dropGroups = []
            return .success(result)
        default:
            return .failure(.notJSON)
        }
        var used = Set<String>()
        for group in answer.groups {
            if group.from.isEmpty || group.name.trimmingCharacters(in: .whitespaces).isEmpty {
                return .failure(.unknownGroup)
            }
            for id in group.from {
                if isImageNumber(id) { return .failure(.imageNumberInFrom) }
                if other.contains(id) { return .failure(.groupFromOtherSplit) }
                if !own.contains(id) { return .failure(.unknownGroup) }
                if !used.insert(id).inserted { return .failure(.groupUsedTwice) }
            }
        }
        result.dropGroups = answer.dropGroups.filter(own.contains)
        if answer.chosen == "B" {
            result.groups = result.groups.map { group in
                var copy = group
                copy.evidence = []
                return copy
            }
        }
        return .success(result)
    }
    // swiftlint:enable cyclomatic_complexity

    /// The entries whose name is over 10 or same-part over 20 characters.
    static func tooLong(_ answer: RoundOneAnswer) -> [ShortenItem] {
        var items: [ShortenItem] = []
        if let name = answer.pileName, name.count > maxNameCharacters {
            items.append(ShortenItem(key: "pile", name: name, samePart: ""))
        }
        for group in answer.groups {
            let samePart = group.samePart ?? ""
            guard let key = group.from.first,
                  group.name.count > maxNameCharacters || samePart.count > maxSamePartCharacters else { continue }
            items.append(ShortenItem(key: key, name: group.name, samePart: samePart))
        }
        return items
    }

    /// An entry that is not a group id (`A1`, `B3`) but has a digit: `7`, `\u{56FE}7`.
    private static func isImageNumber(_ text: String) -> Bool {
        let isGroupId = text.count == 2 && "AB".contains(text.first!) && text.last!.isNumber
        return !isGroupId && text.contains { $0.isNumber }
    }
}
