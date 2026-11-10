import Foundation

/// The evening slots a push can go out in: 21:00 on weekdays, 20:30 on
/// Saturday and Sunday, in the calendar's time zone.
public enum PushSlots {
    public static let days = 7
    /// Tonight counts only when its slot is at least this far away.
    public static let leadTime: TimeInterval = 1800

    /// The next `days` slots, starting tonight when it is `leadTime` away.
    public static func make(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var slots: [Date] = []
        var offset = 0
        while slots.count < days, offset < days + 2 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                let slot = time(on: day, calendar: calendar)
                if slot.timeIntervalSince(now) >= leadTime { slots.append(slot) }
            }
            offset += 1
        }
        return slots
    }

    /// That day's slot time in the calendar's zone.
    public static func time(on day: Date, calendar: Calendar) -> Date {
        // Saturday and Sunday by Gregorian weekday number, whatever the locale's weekend.
        let weekday = calendar.component(.weekday, from: day)
        let weekend = weekday == 1 || weekday == 7
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = weekend ? 20 : 21
        parts.minute = weekend ? 30 : 0
        return calendar.date(from: parts) ?? day
    }

    /// 23:00 to 09:00 is quiet.
    public static func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 23 || hour < 9
    }
}
