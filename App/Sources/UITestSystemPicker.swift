#if DEBUG
import Foundation
import MiraNoteKit

/// `-UITEST -SYSTEM_PICKER_STUB`: the system photo picker runs out of
/// process, where a test cannot pick. A stub pill beside "Add to Canvas"
/// hands over one canned photo instead, through the same queue a system
/// pick takes, loading for `-IMPORT_DELAY` as a grid pick does.
enum UITestSystemPicker {
    static var isOn: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITEST") && arguments.contains("-SYSTEM_PICKER_STUB")
    }

    /// The canned pick's bytes, after the launch's import delay.
    static func load() async -> [Data] {
        let delay = UserDefaults.standard.integer(forKey: "IMPORT_DELAY")
        if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
        return [MockImageStudioService.tinyPNG]
    }
}
#endif
