import Foundation

/// The small metadata line under page covers: "June 21". The cover
/// already says the page's title; the caption carries what the cover
/// cannot -- when it happened.
enum CaptionDate {
    static func string(for date: Date) -> String {
        AppDateFormat.string(from: date, template: "MMMMd")
    }
}
