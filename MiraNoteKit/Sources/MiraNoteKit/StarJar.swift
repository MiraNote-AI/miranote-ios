import CryptoKit
import Foundation

/// One saved page as a star in the jar, with the journal it lives in (the
/// reading route needs both).
public struct JarStar: Identifiable, Equatable, Sendable {
    public let collectionID: MemoryCollection.ID
    public let memory: Memory

    public var id: Memory.ID { memory.id }
}

/// The span the star jar shows. Weeks start where the user's calendar
/// starts them.
public enum JarPeriod: String, CaseIterable, Sendable {
    case week, month

    private var component: Calendar.Component {
        self == .week ? .weekOfYear : .month
    }

    /// The week or month holding `date`.
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// The period `steps` before (negative) or after the one starting at
    /// `interval.start`.
    public func interval(
        shifting interval: DateInterval,
        by steps: Int,
        calendar: Calendar = .current
    ) -> DateInterval {
        let moved = calendar.date(byAdding: component, value: steps, to: interval.start) ?? interval.start
        return self.interval(containing: moved, calendar: calendar)
    }

    /// "Oct 20 - 26", "Sep 29 - Oct 5" or "October 2026" (en dashes), each
    /// date laid out the way `locale` writes it.
    public func label(for interval: DateInterval, locale: Locale, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if self == .month {
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: interval.start)
        }
        let last = interval.end.addingTimeInterval(-1)
        let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let start = formatter.string(from: interval.start)
        formatter.setLocalizedDateFormatFromTemplate(sameMonth ? "d" : "MMMd")
        return "\(start) \u{2013} \(formatter.string(from: last))"
    }
}

public enum StarJar {
    /// The one place that decides which pages are stars: every page on the
    /// shelf (the bin's are gone) that Save has filed -- still one when it
    /// is a draft again, never one that only ever was (#137) -- whose
    /// memory date falls in `interval`, oldest first so a period fills its
    /// jar from the bottom.
    public static func stars(in library: MemoryLibrary, during interval: DateInterval) -> [JarStar] {
        library.collections
            .flatMap { collection in
                collection.memories.map { JarStar(collectionID: collection.id, memory: $0) }
            }
            .filter {
                $0.memory.hasBeenSaved
                    && $0.memory.memoryDate >= interval.start && $0.memory.memoryDate < interval.end
            }
            .sorted {
                ($0.memory.memoryDate, $0.id.uuidString) < ($1.memory.memoryDate, $1.id.uuidString)
            }
    }
}

public extension Memory {
    /// What the mood is judged from: the page's words top to bottom, its
    /// photos' descriptions and its backdrop's, at most 2000 characters.
    /// A page from before the canvas (title and body only) reads as the
    /// blocks the editor would make of it. Empty: nothing to judge.
    var moodText: String {
        let parts = materializedForEditing().items
            .sorted { ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x) }
            .compactMap { item -> String? in
                switch item.content {
                case .text(let block): return block.text
                case .image(let ref): return ref.summary
                case .sticker, .sound: return nil
                }
            } + [backgroundSummary]
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(joined.prefix(2000))
    }

    /// A fingerprint of `text` that stays the same across launches (unlike
    /// `hashValue`): SHA-256, in hex.
    static func moodHash(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
