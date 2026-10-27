import Foundation

public extension String {
    /// The app's own copy for `resource`, from the app's string catalog
    /// (`Localizable.xcstrings` in the main bundle) in the language picked
    /// in Settings > Language rather than the device's, so a change applies
    /// at once. Read inside a view's body, it also redraws that view when
    /// the language changes (`AppSettings` is observable).
    ///
    /// SwiftUI's `Text("...")` needs none of this: it looks its key up in
    /// the environment's locale, which the app root sets from the same
    /// choice. This is for copy built as a `String` -- view models, hints,
    /// receipts, accessibility values.
    init(appCopy resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = AppSettings.shared.language.locale
        self.init(localized: resource)
    }
}
