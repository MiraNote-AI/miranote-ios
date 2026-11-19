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
    /// Every star on the shelf (the bin's are gone) whose memory date falls
    /// in `interval`, oldest first so a period fills its jar from the
    /// bottom.
    public static func stars(in library: MemoryLibrary, during interval: DateInterval) -> [JarStar] {
        library.collections
            .flatMap { collection in
                collection.memories.map { JarStar(collectionID: collection.id, memory: $0) }
            }
            .filter {
                isStar($0.memory)
                    && $0.memory.memoryDate >= interval.start && $0.memory.memoryDate < interval.end
            }
            .sorted {
                ($0.memory.memoryDate, $0.id.uuidString) < ($1.memory.memoryDate, $1.id.uuidString)
            }
    }

    /// Whether a star is dated `date` or later: the jar steps past the
    /// current period only toward one.
    public static func hasStars(in library: MemoryLibrary, from date: Date) -> Bool {
        library.collections.contains { collection in
            collection.memories.contains { isStar($0) && $0.memoryDate >= date }
        }
    }

    /// The one rule for which pages are stars: those Save has filed --
    /// still one when it is a draft again, never one that only ever was
    /// (#137).
    private static func isStar(_ memory: Memory) -> Bool { memory.hasBeenSaved }
}
