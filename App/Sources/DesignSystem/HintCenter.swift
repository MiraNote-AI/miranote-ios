import Foundation

/// First-time hints with the v2.1 graduation rule: a hint shows once, at
/// the moment it applies, and never again. Automated runs (UI tests, the
/// live end-to-end test and the demo recorder) see a hint only when they ask
/// for it with `-HINT <id>`, and never record one as seen.
enum HintCenter {
    private static let key = "miranote.graduatedHints"

    #if DEBUG
    private static var isAutomated: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITEST") || arguments.contains("-DEMO-SAMPLES")
    }
    #endif

    static func shouldShow(_ id: String) -> Bool {
        #if DEBUG
        if isAutomated {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "-HINT"), flag + 1 < arguments.count else { return false }
            return arguments[flag + 1] == id
        }
        #endif
        let graduated = UserDefaults.standard.stringArray(forKey: key) ?? []
        return !graduated.contains(id)
    }

    static func graduate(_ id: String) {
        #if DEBUG
        // A test run must not leave "seen" in the simulator's defaults: the
        // next run's outcome would depend on test order.
        if isAutomated { return }
        #endif
        var graduated = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !graduated.contains(id) else { return }
        graduated.append(id)
        UserDefaults.standard.set(graduated, forKey: key)
    }
}
