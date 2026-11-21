#if DEBUG
import Foundation
import MiraNoteKit

/// What the scripted backend reads of a repeat theme's meta
/// (`RepeatComposeMeta`, snake_case): enough to answer the memory the
/// backend would.
struct RepeatMeta: Decodable {
    struct Theme: Decodable {
        let name: String
        let noun: String
    }

    struct Photo: Decodable {
        let id: String
        let takenAt: String

        private enum CodingKeys: String, CodingKey {
            case id
            case takenAt = "taken_at"
        }
    }

    let mode: String
    let groupKey: String
    let tz: String
    let theme: Theme
    let photos: [Photo]

    private enum CodingKeys: String, CodingKey {
        case mode, tz, theme, photos
        case groupKey = "group_key"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        guard mode == "repeat" else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "not a repeat meta")
        }
        groupKey = try container.decode(String.self, forKey: .groupKey)
        tz = try container.decode(String.self, forKey: .tz)
        theme = try container.decode(Theme.self, forKey: .theme)
        photos = try container.decode([Photo].self, forKey: .photos)
    }

    /// The memory: title "<name> . <months>" as the backend makes it, the
    /// first photo the peak, every photo in the story, one question.
    var memory: TriggerMemory {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz) ?? .current
        let iso = ISO8601DateFormatter()
        let dated = photos.compactMap { photo in iso.date(from: photo.takenAt).map { (photo.id, $0) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        let title = theme.name + TriggerWords.separator + Self.months(dated.map(\.1), calendar: calendar)
        let noun = theme.noun
        let peak = dated.first?.0 ?? ""
        // "keep these <noun>", "three keywords for these <noun>?"
        let keep = "\u{7559}\u{4F4F}\u{8FD9}\u{4E9B}" + noun
        // F0 as the backend writes it: "{n} photos, {n} different days".
        let body = "\(dated.count) \u{5F20}\u{7167}\u{7247}\u{FF0C}"
            + "\(dated.count) \u{4E2A}\u{4E0D}\u{540C}\u{7684}\u{65E5}\u{5B50}"
        let question = "\u{7528}\u{4E09}\u{4E2A}\u{8BCD}\u{5F62}\u{5BB9}\u{8FD9}\u{4E9B}" + noun + "\u{FF1F}"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = "yyyy-MM-dd"
        return TriggerMemory(
            id: groupKey, mode: "repeat", date: dated.last.map { day.string(from: $0.1) } ?? "",
            daypart: Daypart(hour: calendar.component(.hour, from: dated.first?.1 ?? .now)), bucket: "",
            push: .init(title: title, body: body, coverPhotoId: peak),
            story: .init(firstFrameLabel: title,
                         photos: dated.map { .init(id: $0.0, takenAt: $0.1, isPeak: $0.0 == peak) }),
            ending: .init(factLine: title, detail: "",
                          questions: [.init(text: question, type: "one_word", source: "fallback_B1")], ctaLabel: keep),
            facts: [:],
            generation: .init(bodySource: "llm", questionSource: "llm", model: "uitest", costCny: 0, latencyMs: 0))
    }

    /// The backend's `month_range`: one month, a span within a year, or "2025.12-2026.2" across years.
    private static func months(_ dates: [Date], calendar: Calendar) -> String {
        let months = dates.map { calendar.dateComponents([.year, .month], from: $0) }
            .map { ($0.year ?? 0, $0.month ?? 0) }.sorted { $0 < $1 }
        guard let first = months.first, let last = months.last else { return "" }
        let unit = "\u{6708}"
        if first == last { return "\(first.1)" + unit }
        if first.0 == last.0 { return "\(first.1)" + unit + "\u{2013}\(last.1)" + unit }
        return "\(first.0).\(first.1)\u{2013}\(last.0).\(last.1)"
    }
}
#endif
