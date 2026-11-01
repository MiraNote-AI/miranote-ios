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
    private func arguments(_ string: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(lld|@)")
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
                    let chinese = try XCTUnwrap(
                        value(entry, "zh-Hans", plural: "other"), "\(name): \(key) lacks zh-Hans"
                    )
                    XCTAssertEqual(try arguments(chinese), try arguments(key), "\(name): \(key) arguments")
                } else {
                    let chinese = try XCTUnwrap(value(entry, "zh-Hans"), "\(name): \(key) lacks zh-Hans")
                    XCTAssertFalse(chinese.isEmpty, "\(name): \(key)")
                    let english = value(entry, "en") ?? key
                    XCTAssertEqual(try arguments(chinese), try arguments(english), "\(name): \(key) arguments")
                }
            }
        }
    }

    /// Copy written into the code as a literal -- `Text("...")`,
    /// `Button("...")`, `Label("...", ...)`, `TextField("...")`,
    /// `.alert("...")`, `.accessibilityLabel/Hint/Value("...")`,
    /// `Text(copy: "...")`, `String(appCopy: "...")` (one line or `"""`),
    /// `GlassSheet(title: "...")`, `placeholder: "..."` -- has its catalog
    /// entry, so no screen shows English words in Chinese. Best effort:
    /// literals with interpolation are left out (their keys take format
    /// specifiers), as are glyphs and names that are not copy, and the UI
    /// test services.
    func testEveryLiteralCopyInTheSourceIsInTheCatalog() throws {
        let strings = try catalog("Localizable")
        let repository = Self.resources.deletingLastPathComponent().deletingLastPathComponent()
        let call = try NSRegularExpression(pattern: [
            #"(?:\bText\(|\bButton\(|\bLabel\(|\bTextField\(|\.alert\("#,
            #"|\.accessibility(?:Label|Hint|Value)\(|String\(appCopy:\s*|Text\(copy:\s*"#,
            #"|GlassSheet\(title:\s*|\bplaceholder:\s*)"((?:[^"\\]|\\.)*)""#
        ].joined())
        let notCopy: Set<String> = ["A", "Aa", "M", "MiraNote", "#RRGGBB"]
        var missing: [String] = []
        var checked = 0
        for folder in ["App/Sources", "MiraNoteKit/Sources"] {
            let root = repository.appendingPathComponent(folder)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "UITestServices.swift" } ?? []
            for file in files {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (number, line) in lines.enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    let range = NSRange(line.startIndex..., in: line)
                    var literals = call.matches(in: line, range: range)
                        .compactMap { Range($0.range(at: 1), in: line).map { String(line[$0]) } }
                    if line.hasSuffix("String(appCopy: \"\"\"") {
                        literals.append(Self.multiLineLiteral(after: number, in: lines))
                    }
                    for literal in literals where !literal.contains("\\(") && literal.contains(where: \.isLetter) {
                        let key = try Self.unescaped(literal)
                        guard !notCopy.contains(key) else { continue }
                        checked += 1
                        if strings[key] == nil { missing.append("\(file.lastPathComponent):\(number + 1) \(key)") }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 200, "the scan found the code's copy")
        XCTAssertEqual(missing, [], "copy with no catalog entry")
    }

    /// The text of a `"""` literal opening at the end of line `start`: the
    /// closing delimiter's indent stripped, a trailing `\` joining lines.
    private static func multiLineLiteral(after start: Int, in lines: [String]) -> String {
        let body = lines[(start + 1)...].prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("\"\"\"") }
        let closing = lines[min(start + 1 + body.count, lines.count - 1)]
        let indent = closing.prefix { $0 == " " }.count
        var text = ""
        for line in body {
            let content = String(line.dropFirst(indent))
            text += content.hasSuffix("\\") ? String(content.dropLast()) : content + "\n"
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// A Swift string literal's text: `\u{...}`, `\"` and `\\` resolved.
    private static func unescaped(_ literal: String) throws -> String {
        var result = literal.replacingOccurrences(of: #"\""#, with: "\"")
        let scalar = try NSRegularExpression(pattern: #"\\u\{([0-9A-Fa-f]+)\}"#)
        for match in scalar.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result), let hex = Range(match.range(at: 1), in: result),
                  let value = UInt32(result[hex], radix: 16), let character = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(whole, with: String(character))
        }
        return result.replacingOccurrences(of: #"\\"#, with: "\\")
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
        let domain = UserDefaults.standard.persistentDomain(forName: try XCTUnwrap(Bundle.main.bundleIdentifier))
        let storedLanguages = domain?["AppleLanguages"]
        let before = settings.language
        defer {
            settings.language = before
            UserDefaults.standard.set(storedLanguages, forKey: "AppleLanguages")
        }

        let joyful = try XCTUnwrap(value(try XCTUnwrap(catalog("Localizable")["Joyful"]), "zh-Hans"))
        settings.language = .simplifiedChinese
        XCTAssertEqual(Mood.joyful.displayName, joyful)
        settings.language = .english
        XCTAssertEqual(Mood.joyful.displayName, "Joyful")
    }
}
