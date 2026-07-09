import Foundation

/// The small metadata line under page covers: "June 21". The cover
/// already says the page's title; the caption carries what the cover
/// cannot -- when it happened.
enum CaptionDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.string(from: date)
    }
}
