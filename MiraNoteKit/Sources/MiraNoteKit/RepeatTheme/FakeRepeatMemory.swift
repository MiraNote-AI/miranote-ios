import Foundation

/// The catalog keys of a repeat push's content words (Chinese always, as
/// `TriggerContentKey`; the app hands the zh-Hans lookup to the Kit). The
/// zh-Hans values are the backend's (`names.txt`): `Month %lld` is
/// "{m}\u{6708}", and so on.
public enum RepeatContentKey {
    /// The title's months: one month.
    public static let monthOne = "Month %lld"
    /// Several months of one year.
    public static let monthSpan = "Months %1$lld to %2$lld"
    /// Months across a year: year, month, year, month.
    public static let monthYears = "%1$lld.%2$lld to %3$lld.%4$lld"
    /// F0, the body without a detail line: the photo count, once a photo and once a day.
    public static let photosOnDays = "%1$lld photos on %1$lld different days"
    /// The ending's button with the theme's noun.
    public static let keepThese = "Keep these %@"
    /// The noun when the theme has none.
    public static let nounFallback = "moments"
    /// Question B1 with the theme's noun.
    public static let threeKeywords = "Three keywords for these %@?"

    /// Every key, for the catalog test (the app adds them with the repeat pushes).
    public static var all: [String] {
        [monthOne, monthSpan, monthYears, photosOnDays, keepThese, nounFallback, threeKeywords]
    }
}

/// The fake-AI switch's repeat memory, built on the phone with no backend,
/// by the backend's rules: title "<name> . <months>", body F0, no detail
/// line, question B1, "keep these <noun>"; the photo with the highest
/// aesthetics is the peak. Never cached, as `FakeAIMemory`.
public enum FakeRepeatMemory {
    /// - Parameters:
    ///   - aesthetics: photo number -> aesthetics (missing: 0.5).
    ///   - zh: the zh-Hans catalog lookup for `RepeatContentKey`.
    public static func build(meta: RepeatComposeMeta, aesthetics: [String: Double], calendar: Calendar,
                             zh: (String) -> String) -> TriggerMemory {
        let iso = ISO8601DateFormatter()
        let dated = meta.photos.compactMap { photo in iso.date(from: photo.takenAt).map { (photo.id, $0) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        let peak = dated.max { first, second in
            let (firstScore, secondScore) = (aesthetics[first.0] ?? 0.5, aesthetics[second.0] ?? 0.5)
            return firstScore != secondScore ? firstScore < secondScore : first.1 > second.1
        }
        let title = meta.theme.name + TriggerWords.separator + months(dated.map(\.1), calendar: calendar, zh: zh)
        let trimmed = meta.theme.noun.trimmingCharacters(in: .whitespacesAndNewlines)
        let noun = trimmed.isEmpty ? zh(RepeatContentKey.nounFallback) : trimmed
        let photos = dated.map { TriggerMemory.Photo(id: $0.0, takenAt: $0.1, isPeak: $0.0 == peak?.0) }
        return TriggerMemory(
            id: meta.groupKey, mode: RepeatComposeMeta.mode,
            date: dated.last.map { PushPhotoPicker.day($0.1, calendar: calendar) } ?? "",
            daypart: Daypart(hour: calendar.component(.hour, from: peak?.1 ?? .now)), bucket: "",
            push: .init(title: title, body: String(format: zh(RepeatContentKey.photosOnDays), dated.count),
                        coverPhotoId: peak?.0 ?? ""),
            story: .init(firstFrameLabel: title, photos: photos),
            ending: .init(factLine: title, detail: "",
                          questions: [.init(text: String(format: zh(RepeatContentKey.threeKeywords), noun),
                                            type: "one_word", source: "fallback_B1")],
                          ctaLabel: String(format: zh(RepeatContentKey.keepThese), noun)),
            facts: [:],
            generation: .init(bodySource: FakeAIMemory.source, questionSource: FakeAIMemory.source,
                              model: "on-device", costCny: 0, latencyMs: 0))
    }

    /// The local months of `dates` as the title shows them (the backend's
    /// `month_range`): one month, a span within a year, or across years.
    static func months(_ dates: [Date], calendar: Calendar, zh: (String) -> String) -> String {
        let months = dates.map { calendar.dateComponents([.year, .month], from: $0) }
            .map { ($0.year ?? 0, $0.month ?? 0) }
            .sorted { $0 < $1 }
        guard let first = months.first, let last = months.last else { return "" }
        if first == last { return String(format: zh(RepeatContentKey.monthOne), first.1) }
        if first.0 == last.0 { return String(format: zh(RepeatContentKey.monthSpan), first.1, last.1) }
        return String(format: zh(RepeatContentKey.monthYears), first.0, first.1, last.0, last.1)
    }
}
