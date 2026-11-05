import Foundation

/// The catalog keys of the trigger's content words. Content is Chinese
/// always (handoff 7.0): the app looks these up in the zh-Hans catalog,
/// whatever the app language, and hands the Kit the lookup as `zh`.
public enum TriggerContentKey {
    /// F0, the body without a detail line: "N photos, a Friday night" --
    /// the count, then the group's belongs-to weekday and the cover's daypart.
    public static let photosOnWeekday = "%1$lld photos, a %2$@ %3$@"
    /// Question B1: three keywords for that part of the day.
    public static let threeWords = "Three words for that %@: __, __, __"
    /// The ending's button: keep this part of the day.
    public static let keepThis = "Keep this %@"

    public static func daypart(_ daypart: Daypart) -> String {
        switch daypart {
        case .morning: return "Morning"
        case .noon: return "Noon"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    /// The weekdays, Sunday first (`Calendar` weekday 1).
    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// A weekday by its `Calendar` number (1 is Sunday).
    public static func weekday(_ number: Int) -> String {
        weekdays[((number - 1) % 7 + 7) % 7]
    }

    /// Every key, for the catalog test.
    public static var all: [String] {
        [photosOnWeekday, threeWords, keepThis] + Daypart.allCases.map(daypart) + weekdays
            + PushBucket.allCases.map(\.catalogKey)
    }
}

/// The words the backend and the fake AI share: "10.18", "9.05" -- month
/// without, day with a leading zero.
public enum TriggerWords {
    public static let separator = " \u{00B7} "

    public static func shortDate(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        return String(format: "%d.%02d", parts[1], parts[2])
    }

    /// "10.18 . <place>", or the date alone without a place.
    public static func factLine(day: String, place: String?) -> String {
        ([shortDate(day)] + [place].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: separator)
    }
}

/// The fake-AI switch's memory, built on the phone with no backend
/// (handoff 7.5): up to eight of the preselected photos, the best-scoring
/// one as the peak, no detail line (body F0), question B1 (`one_word`).
/// Never cached: the backend's answer for the same photos must not lose
/// to it once the switch is off (`AIResultCache`).
public enum FakeAIMemory {
    public static let maxPhotos = 8
    /// `generation.bodySource` of every memory built here.
    public static let source = "fake"

    /// - Parameters:
    ///   - meta: the meta that would have been sent (numbers, times, place).
    ///   - picks: the preselection, by localIdentifier; `photoIds` maps the
    ///     meta's numbers to them.
    ///   - zh: the zh-Hans catalog lookup for `TriggerContentKey`.
    public static func build(
        meta: ComposeMeta, photoIds: [String: String], picks: [Preselected], calendar: Calendar,
        zh: (String) -> String
    ) -> TriggerMemory {
        let numberOf = Dictionary(photoIds.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let iso = ISO8601DateFormatter()
        let metaPhotos = Dictionary(meta.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        struct Scored {
            let number: String
            let score: Double
            let at: Date
        }
        let scored = picks.compactMap { pick -> Scored? in
            guard let number = numberOf[pick.id], let photo = metaPhotos[number],
                  let date = iso.date(from: photo.takenAt) else { return nil }
            return Scored(number: number, score: pick.score, at: date)
        }
        let byScore = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.at < $1.at }
        let chosen = Array(byScore.prefix(maxPhotos)).sorted { $0.at < $1.at }
        let peak = byScore.first
        // The cover's time gives the daypart; the body's weekday is the group's
        // belongs-to day's (a photo before 04:00 is the night before), as the backend's.
        let coverAt = peak?.at ?? .now
        let daypart = Daypart(hour: calendar.component(.hour, from: coverAt))
        let when = zh(TriggerContentKey.daypart(daypart))
        // `meta.weekday` is 1 Monday ... 7 Sunday; the keys go by `Calendar` (1 Sunday).
        let weekday = zh(TriggerContentKey.weekday(meta.weekday % 7 + 1))
        let fact = TriggerWords.factLine(day: meta.date, place: meta.place)
        let bucket = PushBucket.majority(of: chosen.map { number in
            Set((metaPhotos[number.number]?.labels ?? []).compactMap(BroadCategory.init(rawValue:)))
        })
        let photos = chosen.map {
            TriggerMemory.Photo(id: $0.number, takenAt: $0.at, isPeak: $0.number == peak?.number)
        }
        return TriggerMemory(
            id: meta.groupKey, date: meta.date, daypart: daypart, bucket: zh(bucket.catalogKey),
            push: .init(title: fact + TriggerWords.separator + when,
                        body: String(format: zh(TriggerContentKey.photosOnWeekday), meta.rawCount, weekday, when),
                        coverPhotoId: peak?.number ?? ""),
            story: .init(firstFrameLabel: fact, photos: photos),
            ending: .init(factLine: fact, detail: "",
                          questions: [.init(text: String(format: zh(TriggerContentKey.threeWords), when),
                                            type: "one_word", source: "fallback_B1")],
                          ctaLabel: String(format: zh(TriggerContentKey.keepThis), when)),
            facts: [:],
            generation: .init(bodySource: source, questionSource: source, model: "on-device", costCny: 0,
                              latencyMs: 0)
        )
    }
}

extension TriggerMemory {
    /// Built on the phone by the fake-AI switch (`FakeAIMemory`), not by
    /// the backend.
    public var isFakeMade: Bool { generation?.bodySource == FakeAIMemory.source }
}
