import Foundation
import MiraNoteKit
import XCTest
@testable import MiraNote

/// The Simplified Chinese localization (Settings > Language): every entry of
/// the string catalogs has its zh-Hans translation, with the same format
/// arguments and the plural forms it needs, and lookups in the built app
/// resolve in the chosen language. Expected Chinese is read from the
/// catalog, never written here (committed source stays ASCII).
final class LocalizationCatalogTests: XCTestCase {
    private typealias Entry = [String: Any]

    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private func catalog(_ name: String) throws -> [String: Entry] {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("\(name).xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: Entry])
    }

    /// The value of a plain entry in `language`, or a plural entry's form.
    private func value(_ entry: Entry, _ language: String, plural form: String? = nil) -> String? {
        let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any]
        let unit: [String: Any]?
        if let form {
            let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any]
            unit = (plural?[form] as? [String: Any])?["stringUnit"] as? [String: Any]
        } else {
            unit = localization?["stringUnit"] as? [String: Any]
        }
        guard unit?["state"] as? String == "translated" else { return nil }
        return unit?["value"] as? String
    }

    private func isPlural(_ entry: Entry) -> Bool {
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        return localizations.values.contains { (($0 as? [String: Any])?["variations"]) != nil }
    }

    /// The format arguments a string takes, in order of position: "%1$@"
    /// and "%@" both count as one object argument.
    private func arguments(_ string: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(lld|@)")
        let matches = pattern.matches(in: string, range: NSRange(string.startIndex..., in: string))
        var byPosition: [Int: String] = [:]
        for (index, match) in matches.enumerated() {
            let position = Range(match.range(at: 1), in: string).flatMap { Int(string[$0]) } ?? index + 1
            byPosition[position] = Range(match.range(at: 2), in: string).map { String(string[$0]) }
        }
        return byPosition.keys.sorted().compactMap { byPosition[$0] }
    }

    func testEveryEntryHasASimplifiedChineseTranslation() throws {
        for name in ["Localizable", "InfoPlist"] {
            let strings = try catalog(name)
            XCTAssertFalse(strings.isEmpty, name)
            for (key, entry) in strings {
                XCTAssertNotEqual(entry["extractionState"] as? String, "stale", "\(name): stale entry \(key)")
                if isPlural(entry) {
                    // English needs one and other; Chinese has one form.
                    for form in ["one", "other"] {
                        XCTAssertNotNil(value(entry, "en", plural: form), "\(name): \(key) lacks en \(form)")
                    }
                    let chinese = try XCTUnwrap(value(entry, "zh-Hans", plural: "other"), "\(name): \(key) lacks zh-Hans")
                    XCTAssertEqual(arguments(chinese), arguments(key), "\(name): \(key) arguments")
                } else {
                    let chinese = try XCTUnwrap(value(entry, "zh-Hans"), "\(name): \(key) lacks zh-Hans")
                    XCTAssertFalse(chinese.isEmpty, "\(name): \(key)")
                    XCTAssertEqual(arguments(chinese), arguments(value(entry, "en") ?? key), "\(name): \(key) arguments")
                }
            }
        }
    }

    /// The permission prompts' English in the catalog is Info.plist's own.
    func testInfoPlistCatalogMatchesInfoPlist() throws {
        for (key, entry) in try catalog("InfoPlist") {
            let plist = try XCTUnwrap(Bundle.main.infoDictionary?[key] as? String, key)
            XCTAssertEqual(value(entry, "en"), plist, key)
        }
    }

    /// The built app resolves the catalog per language, plurals included.
    func testTheBuiltCatalogResolvesInEitherLanguage() throws {
        let strings = try catalog("Localizable")
        let chinese = LanguageChoice.simplifiedChinese.locale
        let english = LanguageChoice.english.locale

        let start = try XCTUnwrap(value(try XCTUnwrap(strings["Start a memory"]), "zh-Hans"))
        XCTAssertEqual(String(localized: LocalizedStringResource("Start a memory", locale: chinese)), start)
        XCTAssertEqual(String(localized: LocalizedStringResource("Start a memory", locale: english)), "Start a memory")

        let count = 1
        XCTAssertEqual(String(localized: LocalizedStringResource("\(count) pages", locale: english)), "1 page")
        let pages = try XCTUnwrap(value(try XCTUnwrap(strings["%lld pages"]), "zh-Hans", plural: "other"))
        XCTAssertEqual(String(localized: LocalizedStringResource("\(count) pages", locale: chinese)),
                       pages.replacingOccurrences(of: "%lld", with: "1"))
    }

    /// Copy the Kit builds (a mood's name) comes from the app's catalog in
    /// the language picked in Settings. Restores the simulator's choice.
    func testKitCopyFollowsTheChosenLanguage() throws {
        let settings = AppSettings.shared
        let stored = UserDefaults.standard.object(forKey: "miranote.settings.language")
        let storedLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        let before = settings.language
        defer {
            settings.language = before
            UserDefaults.standard.set(stored, forKey: "miranote.settings.language")
            UserDefaults.standard.set(storedLanguages, forKey: "AppleLanguages")
        }

        let joyful = try XCTUnwrap(value(try XCTUnwrap(catalog("Localizable")["Joyful"]), "zh-Hans"))
        settings.language = .simplifiedChinese
        XCTAssertEqual(Mood.joyful.displayName, joyful)
        settings.language = .english
        XCTAssertEqual(Mood.joyful.displayName, "Joyful")
    }
}
