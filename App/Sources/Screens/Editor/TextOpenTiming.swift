import os
import QuartzCore
import UIKit

/// #162: how long a tap on Text takes to bring the keyboard and the text
/// tools up, and what happens on the way. One open runs from the tap to
/// the keyboard landing (`keyboardDidShow`). Signposts show it in
/// Instruments (Animation Hitches), a log line in Console.app on a phone,
/// and `snapshot` in the -UITEST probe.
@MainActor
enum TextOpenTiming {
    private static let signposter = OSSignposter(subsystem: "ai.miranote.app", category: "TextTool")
    private static let log = Logger(subsystem: "ai.miranote.app", category: "TextTool")

    private static var start: CFTimeInterval?
    private static var interval: OSSignpostIntervalState?
    private static var accessoryMs = -1
    private static var focusMs = -1
    private static var keyboardMs = -1
    private static var keyboardShows = 0
    private static var clearScrolls = 0
    private static var opens = 0
    private static var darkReloads = 0
    private static var observing = false

    /// The Text tool was tapped.
    static func begin() {
        observeKeyboard()
        if let interval { signposter.endInterval("TextOpen", interval) }
        start = CACurrentMediaTime()
        interval = signposter.beginAnimationInterval("TextOpen")
        accessoryMs = -1
        focusMs = -1
        keyboardMs = -1
        keyboardShows = 0
        clearScrolls = 0
    }

    static func markAccessoryShown() {
        guard accessoryMs < 0, let ms = elapsed() else { return }
        accessoryMs = ms
        signposter.emitEvent("accessory")
    }

    static func markFocused() {
        guard focusMs < 0, let ms = elapsed() else { return }
        focusMs = ms
        signposter.emitEvent("focused")
    }

    /// DarkKeyboard swapped a keyboard that was already up.
    static func noteDarkReload() {
        darkReloads += 1
        signposter.emitEvent("darkReload")
    }

    /// The board scrolled the block being written clear of the tools.
    static func noteClearScroll() {
        guard start != nil else { return }
        clearScrolls += 1
        signposter.emitEvent("clearScroll")
    }

    static var snapshot: [String: Any] {
        ["opens": opens, "ms": keyboardMs, "accessoryMs": accessoryMs, "focusMs": focusMs,
         "keyboardMs": keyboardMs, "keyboardShows": keyboardShows, "clearScrolls": clearScrolls,
         "darkReloads": darkReloads, "darkArmed": false]
    }

    private static func elapsed() -> Int? {
        guard let start else { return nil }
        return Int(((CACurrentMediaTime() - start) * 1000).rounded())
    }

    private static func observeKeyboard() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard start != nil else { return }
                keyboardShows += 1
                signposter.emitEvent("keyboardWillShow")
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { keyboardLanded() }
        }
    }

    private static func keyboardLanded() {
        guard keyboardMs < 0, let ms = elapsed() else { return }
        keyboardMs = ms
        opens += 1
        if let interval { signposter.endInterval("TextOpen", interval) }
        interval = nil
        log.info("""
            text open ms=\(ms) accessory=\(accessoryMs) focus=\(focusMs) \
            shows=\(keyboardShows) reloads=\(darkReloads) open=\(opens)
            """)
    }
}
