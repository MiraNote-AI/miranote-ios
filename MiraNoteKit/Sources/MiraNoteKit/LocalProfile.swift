import Foundation
import Observation

/// The Profile screen's name and avatar (handoff 2026-10-24, screens 06-07),
/// kept on the device: the app has no account yet. The name lives in
/// UserDefaults, the avatar image in its own folder (not the pages' image
/// folder, so a sweep of unreferenced page images can never take it).
@Observable
public final class LocalProfile {
    public static let nameLimit = 40

    public enum SaveError: Error {
        case invalidName
    }

    enum Key {
        static let displayName = "miranote.profile.displayName"
        static let avatarFileName = "miranote.profile.avatarFileName"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public let images: ImageFileStore

    /// Empty until the user saves a name.
    public private(set) var displayName: String
    public private(set) var avatarFileName: String?

    public init(defaults: UserDefaults = .standard, images: ImageFileStore = LocalProfile.defaultImages) {
        self.defaults = defaults
        self.images = images
        displayName = defaults.string(forKey: Key.displayName) ?? ""
        avatarFileName = defaults.string(forKey: Key.avatarFileName)
    }

    public static var defaultImages: ImageFileStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ImageFileStore(directory: documents.appendingPathComponent("MiraNoteProfile", isDirectory: true))
    }

    /// The name as it would be saved -- trimmed, 1 to `nameLimit`
    /// characters -- or nil when it cannot be.
    public static func validName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= nameLimit else { return nil }
        return trimmed
    }

    /// Save is offered for a valid name that differs from the saved one, or
    /// with a new avatar.
    public func canSave(name: String, hasNewAvatar: Bool) -> Bool {
        guard let valid = Self.validName(name) else { return false }
        return hasNewAvatar || valid != displayName
    }

    /// Writes the new avatar (if any) before anything else changes, so a
    /// failed write leaves the saved profile as it was.
    public func save(name: String, avatar: Data?) throws {
        guard let valid = Self.validName(name) else { throw SaveError.invalidName }
        if let avatar {
            let fileName = try images.save(avatar, id: UUID())
            if let old = avatarFileName { images.delete(fileName: old) }
            avatarFileName = fileName
            defaults.set(fileName, forKey: Key.avatarFileName)
        }
        displayName = valid
        defaults.set(valid, forKey: Key.displayName)
    }

    /// The saved avatar's bytes; nil without one or when its file is gone.
    public func loadAvatar() -> Data? {
        avatarFileName.flatMap { images.data(forFileName: $0) }
    }
}
