import XCTest
@testable import MiraNoteKit

final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "settings-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsAreSystemEnglishAndOne() {
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en-US"])
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.textScale, 1)
    }

    /// Until a language is picked, the device decides -- the way iOS
    /// matches an app's localizations -- and nothing is stored.
    func testUnchosenLanguageFollowsTheDevice() {
        XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).language,
                       .simplifiedChinese)
        XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["fr-FR", "zh-Hans-CN"]).language,
                       .simplifiedChinese)
        XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["zh-Hant-TW"]).language, .english)
        XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["ja-JP"]).language, .english)
        XCTAssertNil(defaults.string(forKey: "miranote.settings.language"))
    }

    func testAChosenLanguageWinsOverTheDevice() {
        AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).language = .english
        XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).language, .english)
    }

    func testChoicesPersistAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .sunlitPop
        settings.language = .simplifiedChinese
        settings.setTextScale(1.15)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .sunlitPop)
        XCTAssertEqual(reloaded.language, .simplifiedChinese)
        XCTAssertEqual(reloaded.textScale, 1.15, accuracy: 0.0001)
        XCTAssertEqual(defaults.string(forKey: "miranote.settings.appearance"), "sunlitPop")
        XCTAssertEqual(defaults.string(forKey: "miranote.settings.language"), "zh-CN")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"], "system UI follows next launch")
    }

    func testTextScaleIsClampedWhenSetAndWhenRead() {
        let settings = AppSettings(defaults: defaults)
        settings.setTextScale(3)
        XCTAssertEqual(settings.textScale, AppSettings.textScaleRange.upperBound)
        settings.setTextScale(0.1)
        XCTAssertEqual(settings.textScale, AppSettings.textScaleRange.lowerBound)
        settings.setTextScale(.nan)
        XCTAssertEqual(settings.textScale, 1)

        defaults.set(9.0, forKey: "miranote.settings.textScale")
        XCTAssertEqual(AppSettings(defaults: defaults).textScale, AppSettings.textScaleRange.upperBound)
    }

    func testUnknownStoredValuesReadAsDefaults() {
        defaults.set("midnightJournal", forKey: "miranote.settings.appearance")
        defaults.set("fr-FR", forKey: "miranote.settings.language")
        defaults.set("big", forKey: "miranote.settings.textScale")

        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en-US"])
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.textScale, 1)
    }
}

final class LocalProfileTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() {
        suiteName = "profile-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeProfile() -> LocalProfile {
        LocalProfile(defaults: defaults, images: ImageFileStore(directory: directory))
    }

    func testStartsWithoutNameOrAvatar() {
        let profile = makeProfile()
        XCTAssertEqual(profile.displayName, "")
        XCTAssertNil(profile.avatarFileName)
        XCTAssertNil(profile.loadAvatar())
    }

    func testNameIsTrimmedAndLimited() {
        XCTAssertEqual(LocalProfile.validName("  Ada \n"), "Ada")
        XCTAssertNil(LocalProfile.validName(""))
        XCTAssertNil(LocalProfile.validName("   \n "))
        XCTAssertNotNil(LocalProfile.validName(String(repeating: "a", count: LocalProfile.nameLimit)))
        XCTAssertNil(LocalProfile.validName(String(repeating: "a", count: LocalProfile.nameLimit + 1)))
    }

    func testSaveIsOfferedOnlyForAValidChange() throws {
        let profile = makeProfile()
        XCTAssertFalse(profile.canSave(name: "", hasNewAvatar: true), "a name is required")
        XCTAssertTrue(profile.canSave(name: "Ada", hasNewAvatar: false))

        try profile.save(name: "Ada", avatar: nil)
        XCTAssertFalse(profile.canSave(name: " Ada ", hasNewAvatar: false), "unchanged once trimmed")
        XCTAssertTrue(profile.canSave(name: "Ada", hasNewAvatar: true))
        XCTAssertTrue(profile.canSave(name: "Ada L", hasNewAvatar: false))
    }

    func testSavePersistsNameAndAvatarAndReplacesTheOldFile() throws {
        let profile = makeProfile()
        try profile.save(name: " Ada ", avatar: Data([1, 2, 3]))
        let first = try XCTUnwrap(profile.avatarFileName)

        let reloaded = makeProfile()
        XCTAssertEqual(reloaded.displayName, "Ada")
        XCTAssertEqual(reloaded.loadAvatar(), Data([1, 2, 3]))

        try reloaded.save(name: "Ada", avatar: Data([4]))
        XCTAssertEqual(reloaded.loadAvatar(), Data([4]))
        XCTAssertFalse(ImageFileStore(directory: directory).exists(fileName: first), "the old avatar is removed")
    }

    func testInvalidNameChangesNothing() throws {
        let profile = makeProfile()
        try profile.save(name: "Ada", avatar: nil)
        XCTAssertThrowsError(try profile.save(name: "  ", avatar: Data([1])))
        XCTAssertEqual(profile.displayName, "Ada")
        XCTAssertNil(profile.avatarFileName)
    }

    func testAMissingAvatarFileReadsAsNoAvatar() throws {
        let profile = makeProfile()
        try profile.save(name: "Ada", avatar: Data([1]))
        try FileManager.default.removeItem(at: directory)
        XCTAssertNil(makeProfile().loadAvatar())
    }
}
