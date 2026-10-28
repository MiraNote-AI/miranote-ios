import Foundation
import Observation

/// Appearance choices of the Settings screen (handoff 2026-10-24, screen 04).
public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, forest, sunlitPop
}

/// Language choices of the Settings screen (handoff 2026-10-24, screen 05).
public enum LanguageChoice: String, CaseIterable, Sendable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"

    /// The app bundle's localization for this language.
    public var localization: String {
        switch self {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    /// The locale the app's copy, dates and numbers use: its language picks
    /// the catalog's localization (`zh-Hans`), its region the formats.
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .simplifiedChinese: return Locale(identifier: "zh-Hans-CN")
        }
    }

    /// The language of the app's localization iOS resolved (from the app's
    /// own language in iOS Settings, or the device's): Simplified Chinese,
    /// or English for anything else.
    public init(localization: String?) {
        self = localization?.hasPrefix("zh-Hans") == true ? .simplifiedChinese : .english
    }
}

/// The Settings screens' preferences, persisted in UserDefaults under
/// `miranote.settings.*` -- but the language, which is the app's
/// `AppleLanguages`: the one iOS Settings > MiraNote > Language writes too.
/// The app draws its theme from the appearance and its copy's language from
/// `language` (see `String(appCopy:)`); applying the text scale app-wide
/// comes in a follow-up PR.
@Observable
public final class AppSettings {
    /// The app's preferences. String lookups outside the view tree read the
    /// language here, so there is one instance for the whole app.
    public static let shared: AppSettings = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            // English unless the test's launch asks for a language
            // (`-AppleLanguages`), or picked one before its own relaunch:
            // a Chinese simulator or an aborted language test never turns
            // the English-label suite Chinese.
            let picked = storeDefaults.persistentDomain(forName: uiTestSuite)?[Key.appleLanguages] as? [String]
            let asked = ProcessInfo.processInfo.arguments.contains("-AppleLanguages")
                ? Bundle.main.preferredLocalizations : nil
            return AppSettings(defaults: storeDefaults, preferredLocalizations: picked ?? asked ?? ["en"])
        }
        #endif
        return AppSettings(defaults: storeDefaults)
    }()

    /// Where the settings (and the profile) are kept: the app's defaults.
    /// Under -UITEST, a suite of their own emptied at launch -- unless
    /// `-KEEP_SETTINGS` (a test's own relaunch) -- so no run sees an
    /// earlier one's choices.
    public static let storeDefaults: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            if !ProcessInfo.processInfo.arguments.contains("-KEEP_SETTINGS") {
                UserDefaults.standard.removePersistentDomain(forName: uiTestSuite)
            }
            return UserDefaults(suiteName: uiTestSuite) ?? .standard
        }
        #endif
        return .standard
    }()

    static let uiTestSuite = "MiraNote.UITest.settings"

    /// The text-size slider's range: 1.0 sits where the handoff draws the
    /// thumb (106 of 238 pt along the rail).
    public static let textScaleRange: ClosedRange<Double> = 0.8...1.25
    public static let textScaleStep = 0.05

    enum Key {
        static let appearance = "miranote.settings.appearance"
        static let textScale = "miranote.settings.textScale"
        static let appleLanguages = "AppleLanguages"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var appearance: AppearanceChoice {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// The app's copy follows at once. A pick is stored as the app's
    /// preferred language, so what iOS draws for the app -- permission
    /// prompts, the photo picker, system buttons -- follows from the next
    /// launch, and iOS Settings shows it.
    public var language: LanguageChoice {
        didSet { defaults.set([language.localization], forKey: Key.appleLanguages) }
    }

    /// Always inside `textScaleRange`; set it with `setTextScale(_:)`.
    public private(set) var textScale: Double

    /// The language is the localization iOS resolved for the app at launch
    /// (its `AppleLanguages`, else the device's languages). Unknown stored
    /// values read as the defaults: system, 1.0.
    public init(
        defaults: UserDefaults = .standard,
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations
    ) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceChoice.init) ?? .system
        language = LanguageChoice(localization: preferredLocalizations.first)
        textScale = Self.clamped((defaults.object(forKey: Key.textScale) as? Double) ?? 1)
    }

    public func setTextScale(_ value: Double) {
        textScale = Self.clamped(value)
        defaults.set(textScale, forKey: Key.textScale)
    }

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, textScaleRange.lowerBound), textScaleRange.upperBound)
    }
}
