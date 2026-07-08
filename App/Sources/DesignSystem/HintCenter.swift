import Foundation

/// First-time hints with the v2.1 graduation rule: a hint shows once, at
/// the moment it applies, and never again. UI tests never see hints.
enum HintCenter {
    private static let key = "miranote.graduatedHints"

    static func shouldShow(_ id: String) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") { return false }
        #endif
        let graduated = UserDefaults.standard.stringArray(forKey: key) ?? []
        return !graduated.contains(id)
    }

    static func graduate(_ id: String) {
        var graduated = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !graduated.contains(id) else { return }
        graduated.append(id)
        UserDefaults.standard.set(graduated, forKey: key)
    }
}
