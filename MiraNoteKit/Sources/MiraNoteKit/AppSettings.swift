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
}

/// The Settings screens' preferences, persisted in UserDefaults under
/// `miranote.settings.*`. They are stored and shown only: applying the
/// appearance (Forest, Sunlit Pop theming), the language (zh-CN copy) and
/// the text scale app-wide comes in follow-up PRs.
@Observable
public final class AppSettings {
    /// The text-size slider's range: 1.0 sits where the handoff draws the
    /// thumb (106 of 238 pt along the rail).
    public static let textScaleRange: ClosedRange<Double> = 0.8...1.25
    public static let textScaleStep = 0.05

    enum Key {
        static let appearance = "miranote.settings.appearance"
        static let language = "miranote.settings.language"
        static let textScale = "miranote.settings.textScale"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var appearance: AppearanceChoice {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    public var language: LanguageChoice {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    /// Always inside `textScaleRange`; set it with `setTextScale(_:)`.
    public private(set) var textScale: Double

    /// Unknown stored values read as the defaults: system, en-US, 1.0.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceChoice.init) ?? .system
        language = defaults.string(forKey: Key.language).flatMap(LanguageChoice.init) ?? .english
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
