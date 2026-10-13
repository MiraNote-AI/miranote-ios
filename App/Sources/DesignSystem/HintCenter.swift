import Foundation

/// First-time hints with the v2.1 graduation rule: a hint shows once, at
/// the moment it applies, and never again. UI tests see a hint only when they
/// ask for it with `-HINT <id>`.
enum HintCenter {
    private static let key = "miranote.graduatedHints"

    static func shouldShow(_ id: String) -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") {
            guard let flag = arguments.firstIndex(of: "-HINT"), flag + 1 < arguments.count else { return false }
            return arguments[flag + 1] == id
        }
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
