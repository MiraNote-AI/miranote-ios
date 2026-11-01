import Foundation
import Observation

/// A tapped push waiting to open: Home watches `pending` and opens the
/// story once it is up -- also after a cold launch from the tap.
@MainActor
@Observable
final class TriggerLaunchRouter {
    static let shared = TriggerLaunchRouter()

    /// The push to open; Home clears it when it takes it.
    var pending: String?

    private init() {
        #if DEBUG
        // `-TRIGGER-OPEN-PUSH <id | latest>` goes through the same path as
        // a tap (UI tests).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-TRIGGER-OPEN-PUSH"), arguments.indices.contains(index + 1) {
            pending = arguments[index + 1]
        }
        #endif
    }
}
