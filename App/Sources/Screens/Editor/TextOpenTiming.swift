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
    private static var toolsVisibleMs = -1
    private static var focusMs = -1
    private static var keyboardMs = -1
    private static var willShowMs = -1
    private static var riseMs = -1
    private static var riseCurve = -1
    private static var lateReloads = 0
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
        toolsVisibleMs = -1
        focusMs = -1
        keyboardMs = -1
        willShowMs = -1
        riseMs = -1
        riseCurve = -1
        lateReloads = 0
        keyboardShows = 0
        clearScrolls = 0
    }

    static func markAccessoryShown() {
        guard accessoryMs < 0, let ms = elapsed() else { return }
        accessoryMs = ms
        signposter.emitEvent("accessory")
    }

    /// The tools can be seen (and tapped).
    static func markToolsVisible() {
        guard toolsVisibleMs < 0, let ms = elapsed() else { return }
        toolsVisibleMs = ms
        signposter.emitEvent("toolsVisible")
    }

    static func markFocused() {
        guard focusMs < 0, let ms = elapsed() else { return }
        focusMs = ms
        signposter.emitEvent("focused")
    }

    /// The keyboard was reloaded to swap its appearance.
    static func noteDarkReload() {
        darkReloads += 1
        // After the rise began: the keyboard is swapped in plain sight.
        if willShowMs >= 0 { lateReloads += 1 }
        signposter.emitEvent("darkReload")
    }

    /// The board scrolled the block being written clear of the tools.
    static func noteClearScroll() {
        guard start != nil else { return }
        clearScrolls += 1
        signposter.emitEvent("clearScroll")
    }

    // MARK: The page as a session ends

    private static var cardHeight: CGFloat = 0
    private static var exitFrom: CGFloat?
    private static var exitShrink: CGFloat = 0

    /// The card holding the page has this height now. Once the session
    /// has ended (not writing) and until the keyboard is gone, how far it
    /// is below its height when the session began (it should hold still).
    static func noteCardHeight(_ height: CGFloat, writing: Bool) {
        if let exitFrom, !writing { exitShrink = max(exitShrink, exitFrom - height) }
        if exitFrom == nil { cardHeight = height }
    }

    /// A writing session began on a card of the last noted height.
    static func noteSessionBegan() {
        observeKeyboard()
        exitFrom = cardHeight
        exitShrink = 0
    }

    static var snapshot: [String: Any] {
        ["opens": opens, "ms": keyboardMs, "accessoryMs": accessoryMs, "toolsVisibleMs": toolsVisibleMs,
         "focusMs": focusMs,
         "keyboardMs": keyboardMs, "willShowMs": willShowMs, "riseMs": riseMs, "riseCurve": riseCurve,
         "lateReloads": lateReloads,
         "keyboardShows": keyboardShows, "clearScrolls": clearScrolls,
         "darkReloads": darkReloads,
         "exitShrink": Int(exitShrink.rounded())]
    }

    private static func elapsed() -> Int? {
        guard let start else { return nil }
        return Int(((CACurrentMediaTime() - start) * 1000).rounded())
    }

    private static func observeKeyboard() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
            // The system's own rise: how long, on which curve.
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
            let curve = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
            MainActor.assumeIsolated {
                guard start != nil else { return }
                keyboardShows += 1
                if willShowMs < 0, let ms = elapsed() {
                    willShowMs = ms
                    riseMs = Int(((duration ?? -0.001) * 1000).rounded())
                    riseCurve = curve ?? -1
                }
                signposter.emitEvent("keyboardWillShow")
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { keyboardLanded() }
        }
        center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { exitFrom = nil }
        }
    }

    private static func keyboardLanded() {
        guard keyboardMs < 0, let ms = elapsed() else { return }
        keyboardMs = ms
        opens += 1
        if let interval { signposter.endInterval("TextOpen", interval) }
        interval = nil
        log.info("""
            text open ms=\(ms) accessory=\(accessoryMs) focus=\(focusMs) willShow=\(willShowMs) \
            rise=\(riseMs) curve=\(riseCurve) \
            shows=\(keyboardShows) reloads=\(darkReloads) open=\(opens)
            """)
    }
}
