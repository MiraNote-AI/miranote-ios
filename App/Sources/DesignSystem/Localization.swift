import MiraNoteKit
import SwiftUI

extension Text {
    /// App copy handed over as a `String` (a component's label, a pill's
    /// word): looked up in the string catalog by its English words in the
    /// environment's language. Words with no entry -- copy the Kit already
    /// localized, user content -- show as given.
    init(copy: String) {
        self.init(LocalizedStringKey(copy))
    }
}

/// Dates in the app's language (Settings > Language), laid out the way it
/// writes them: the template "MMMMd" reads "June 21" in English and
/// month-day order with its own marks in Chinese.
enum AppDateFormat {
    private static var formatters: [String: DateFormatter] = [:]

    static func string(from date: Date, template: String) -> String {
        let locale = AppSettings.shared.language.locale
        let key = "\(locale.identifier) \(template)"
        if let formatter = formatters[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter.string(from: date)
    }
}
