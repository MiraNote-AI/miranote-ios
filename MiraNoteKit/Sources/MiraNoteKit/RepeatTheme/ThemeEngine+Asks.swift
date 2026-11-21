import CryptoKit
import Foundation

/// Round 1 inside a theme run (spec 6.5, D1-D7): which piles and themes are
/// asked, the sample and request, a stored answer reused for the same
/// question, the checks, one shorten round, and the library update.
extension ThemeEngine {
    /// A grown theme's list over the list Qwen last saw: at this, re-ask (C5).
    static let growth = 1.5
    /// The backend's limits for one round-1 call.
    static let maxSample = 20
    static let maxOldGroups = 12
    static let maxShorten = 7
    /// Round images, long side.
    static let imagePixels = 336

    /// What tonight's clustering gave, for the asks.
    struct Scene {
        let piles: [Pile]
        let moments: [String: Moment]
        let photos: [String: ThemePhoto]
        let calendar: Calendar
    }

    /// One round-1 question: a pile no theme follows (`big` nil), or a
    /// grown theme's own part of the pile it follows.
    struct Ask {
        let pile: Pile
        let big: ThemeRow?
        /// For the run's failure lines.
        let label: String
    }

    struct AskOutcome {
        var sent = false
        var failure: String?
        /// The whole library after the answer; nil when nothing changed.
        var rows: [ThemeRow]?
    }

    /// The questions of tonight (D1): every pile no theme follows (piles
    /// have 5 days by construction), and every followed big theme whose list
    /// is at least 1.5 times what Qwen last saw, sampled from its own part
    /// of the pile. A sensitive or blocked theme is never asked (D5).
    static func asks(_ claim: ClaimResult, rows: [ThemeRow], scene: Scene) -> [Ask] {
        var asks = claim.newPiles.map { Ask(pile: scene.piles[$0], big: nil, label: "New pile \($0 + 1)") }
        for row in rows where row.kind == .big && row.status != .sensitive && row.status != .blocked {
            guard let index = claim.follows[row.id], row.lastAskedCount > 0,
                  Double(row.members.count) >= growth * Double(row.lastAskedCount) else { continue }
            let pile = scene.piles[index]
            let followers = claim.follows.values.filter { $0 == index }.count
            guard let part = followers == 1 ? pile : Self.part(of: row, in: pile, moments: scene.moments) else {
                continue
            }
            asks.append(Ask(pile: part, big: row, label: "Theme \(row.name)"))
        }
        return asks
    }

    /// The moments of `pile` that hold a photo of the row's list, as a pile.
    static func part(of row: ThemeRow, in pile: Pile, moments: [String: Moment]) -> Pile? {
        let members = Set(row.members)
        let own = pile.momentIds.compactMap { moments[$0] }
            .filter { $0.photoIds.contains(where: members.contains) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        guard let length = own.first?.vector.count else { return nil }
        var perDay: [String: Int] = [:]
        for moment in own { perDay[moment.day, default: 0] += 1 }
        var sum = [Double](repeating: 0, count: length)
        for moment in own where moment.vector.count == length {
            for (offset, value) in moment.vector.enumerated() { sum[offset] += Double(value) }
        }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return Pile(momentIds: own.map(\.id), days: perDay.count,
                    maxDayShare: Double(perDay.values.max() ?? 0) / Double(own.count), height: pile.height,
                    center: sum.map { Float(norm > 0 ? $0 / norm : $0) })
    }

    /// Asks one question and folds the answer into `rows`.
    func ask(_ ask: Ask, rows: [ThemeRow], scene: Scene) async -> AskOutcome {
        let groups = PileSplits.make(ask.pile, moments: scene.moments, calendar: scene.calendar)
        var aesthetics: [String: Double] = [:]
        for id in ask.pile.momentIds { aesthetics[id] = scene.photos[id]?.aesthetics }
        let sample = Array(ThemeSampler.pick(ask.pile, moments: scene.moments, a: groups.a, b: groups.b,
                                             aesthetics: aesthetics, max: Self.maxSample).prefix(Self.maxSample))
        guard !sample.isEmpty else { return AskOutcome(failure: "\(ask.label): no photo to send") }
        let old = ask.big.flatMap { Self.oldNames($0, rows: rows) }
        let request = RoundOneRequest.make(pile: ask.pile, moments: scene.moments, a: groups.a, b: groups.b,
                                           photos: sample, old: old)
        let key = Self.key(themeId: ask.big?.id, sample: sample, old: old)

        var outcome = AskOutcome()
        let answer: RoundOneAnswer
        switch await roundOne(request, key: key, offered: groups, themeId: ask.big?.id, sent: &outcome.sent) {
        case .success(let valid): answer = valid
        case .failure(let reason):
            outcome.failure = "\(ask.label): \(reason.text)"
            return outcome
        }
        let named: RoundOneAnswer
        switch await shortened(answer, key: key, themeId: ask.big?.id) {
        case .success(let short): named = short
        case .failure(let reason):
            outcome.failure = "\(ask.label): \(reason.text)"
            return outcome
        }

        let before = Set(rows.map(\.id))
        var updated = ThemeLibrary.apply(named, to: ask.big, pile: ask.pile, moments: scene.moments, groups: groups,
                                         sample: sample, existing: rows)
        let parentId = ask.big?.id ?? updated.first { $0.kind == .big && !before.contains($0.id) }?.id
        if let parentId, let parent = updated.first(where: { $0.id == parentId }) {
            // Small lists by their rule, as every later run will make them.
            for index in updated.indices where updated[index].parentId == parentId
                && updated[index].status != .retired {
                guard let rule = updated[index].rule else { continue }
                updated[index].members = SubThemeRule.members(rule, in: parent.members, moments: scene.moments,
                                                              photosById: scene.photos, calendar: scene.calendar)
            }
        }
        outcome.rows = updated
        return outcome
    }

    /// The names Qwen gave last time (spec 6.5): the big row's and its small
    /// rows', blank ones left out, at most 12 groups; nil without a name.
    static func oldNames(_ big: ThemeRow, rows: [ThemeRow]) -> RoundOneRequest.Old? {
        guard !big.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var seen = Set<String>()
        let groups = rows.filter { $0.kind == .small && $0.parentId == big.id }.map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }
        return RoundOneRequest.Old(pileName: big.name, groups: Array(groups.prefix(maxOldGroups)))
    }

    /// The re-ask key (decision 10): the same theme (or a new pile), the
    /// same sampled moments and the same old names ask the same question.
    static func key(themeId: String?, sample: [SampledPhoto], old: RoundOneRequest.Old?) -> String {
        let names = old.map { ([$0.pileName] + $0.groups).joined(separator: "|") } ?? ""
        let text = [themeId ?? "new", sample.map(\.momentId).joined(separator: ","), names].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return "round1-" + digest.prefix(16)
    }

    // MARK: - Calls

    /// Why an ask did not give an answer to use.
    enum AskFailure: Error {
        case unreadableImage
        case call(ThemeRoundError)
        case answer(RoundOneProblem)

        var text: String {
            switch self {
            case .unreadableImage: return "a photo could not be read for round 1"
            case .call(let error): return "round 1 call failed (\(Self.describe(error)))"
            case .answer(let problem): return "round 1 answer not used (\(problem.rawValue))"
            }
        }

        static func describe(_ error: ThemeRoundError) -> String {
            switch error {
            case .unreachable: return "unreachable"
            case .unauthorized: return "unauthorized"
            case .rateLimited: return "rate limited"
            case .badRequest: return "bad request"
            case .model(let reason, _): return "model \(reason)"
            case .server(let status): return "server \(status)"
            }
        }
    }

    /// The checked answer: from the round log when this question was answered
    /// before (D4), else from the backend. Every answer the backend gives is
    /// logged, with its problem when it is not usable (so it is never
    /// reused); a failed call logs nothing and is simply asked again.
    private func roundOne(_ request: RoundOneRequest, key: String, offered: (a: [SplitGroup], b: [SplitGroup]),
                          themeId: String?, sent: inout Bool) async -> Result<RoundOneAnswer, AskFailure> {
        if let stored = deps.rounds.answer(for: key) {
            return Self.checked(stored.reply, offered: offered).mapError { .answer($0) }
        }
        var images: [(n: Int, jpeg: Data)] = []
        for number in request.photoIds.keys.sorted() {
            guard let id = request.photoIds[number], let data = await deps.imageData(id),
                  let jpeg = UploadImage.prepare(data, maxPixel: Self.imagePixels) else {
                return .failure(.unreadableImage)
            }
            images.append((number, jpeg))
        }
        sent = true
        let reply: RoundReply
        do {
            reply = try await deps.client.roundOne(request, images: images)
        } catch {
            return .failure(.call(error as? ThemeRoundError ?? .unreachable))
        }
        let result = Self.checked(reply.reply, offered: offered)
        try? deps.rounds.append(RoundLogEntry(at: deps.now(), kind: "round1", themeId: themeId, key: key,
                                              reply: reply.reply, usage: reply.usage, problem: Self.problem(result),
                                              where: reply.where))
        return result.mapError { .answer($0) }
    }

    private static func checked(_ text: String, offered: (a: [SplitGroup], b: [SplitGroup]))
        -> Result<RoundOneAnswer, RoundOneProblem> {
        RoundOneAnswer.parse(text).flatMap { RoundOneValidator.validate($0, offered: offered) }
    }

    /// Names over 10 characters (or a same-part over 20) are sent once to be
    /// shortened (D6). A group still too long after that is dropped; a pile
    /// name still too long fails the ask (`tooLong`, asked again next run).
    private func shortened(_ answer: RoundOneAnswer, key: String,
                           themeId: String?) async -> Result<RoundOneAnswer, AskFailure> {
        let long = RoundOneValidator.tooLong(answer)
        guard !long.isEmpty else { return .success(answer) }
        let shortenKey = key + "-shorten"
        let text: String
        if let stored = deps.rounds.answer(for: shortenKey) {
            text = stored.reply
        } else {
            let reply: RoundReply
            do {
                reply = try await deps.client.shorten(Array(long.prefix(Self.maxShorten)))
            } catch {
                return .failure(.call(error as? ThemeRoundError ?? .unreachable))
            }
            text = reply.reply
            var problem: RoundOneProblem?
            if let fixed = Self.applyShortened(text, to: answer) {
                problem = Self.pileTooLong(fixed) ? .tooLong : nil
            } else {
                problem = .notJSON
            }
            try? deps.rounds.append(RoundLogEntry(at: deps.now(), kind: "shorten", themeId: themeId, key: shortenKey,
                                                  reply: text, usage: reply.usage, problem: problem, where: [:]))
        }
        var fixed = Self.applyShortened(text, to: answer) ?? answer
        fixed.groups = fixed.groups.filter {
            $0.name.count <= RoundOneValidator.maxNameCharacters
                && ($0.samePart ?? "").count <= RoundOneValidator.maxSamePartCharacters
        }
        return Self.pileTooLong(fixed) ? .failure(.answer(.tooLong)) : .success(fixed)
    }

    private static func problem(_ result: Result<RoundOneAnswer, RoundOneProblem>) -> RoundOneProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    private static func pileTooLong(_ answer: RoundOneAnswer) -> Bool {
        (answer.pileName?.count ?? 0) > RoundOneValidator.maxNameCharacters
    }

    /// `answer` with the shortened names put back by key (`pile`, or a
    /// group's first `from` id); nil when the reply has no items object.
    static func applyShortened(_ text: String, to answer: RoundOneAnswer) -> RoundOneAnswer? {
        struct Item: Decodable {
            let key: String?
            let name: String?
            let samePart: String?
            private enum CodingKeys: String, CodingKey {
                case key, name
                case samePart = "same_part"
            }
        }
        struct Items: Decodable {
            let items: [Item]
        }
        guard let object = RoundOneAnswer.firstObject(in: text),
              let decoded = try? JSONDecoder().decode(Items.self, from: Data(object.utf8)) else { return nil }
        var fixed = answer
        for item in decoded.items {
            guard let key = item.key, let name = item.name, !name.isEmpty else { continue }
            if key == "pile" {
                fixed.pileName = name
            } else if let index = fixed.groups.firstIndex(where: { $0.from.first == key }) {
                fixed.groups[index].name = name
                if let samePart = item.samePart { fixed.groups[index].samePart = samePart }
            }
        }
        return fixed
    }
}
