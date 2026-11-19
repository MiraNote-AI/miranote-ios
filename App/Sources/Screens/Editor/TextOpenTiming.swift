import os
import QuartzCore
import UIKit

/// #162: how long a tap on Text takes to bring the keyboard and the text
/// tools up, and what happens on the way. One open runs from the tap to
/// the keyboard landing (`keyboardDidShow`). Signposts show it in
/// Instruments (Animation Hitches), in Release too, since Instruments
/// profiles Release builds. Debug builds also log a line in Console.app
/// and fill `snapshot` for the -UITEST probe.
@MainActor
enum TextOpenTiming {
    private static let signposter = OSSignposter(subsystem: "ai.miranote.app", category: "TextTool")

    private static var start: CFTimeInterval?
    private static var interval: OSSignpostIntervalState?
    // The first time of each mark: each event is signposted once per open.
    private static var accessoryMs = -1
    private static var toolsVisibleMs = -1
    private static var focusMs = -1
    private static var observing = false

    #if DEBUG
    private static let log = Logger(subsystem: "ai.miranote.app", category: "TextTool")
    private static var keyboardMs = -1
    private static var willShowMs = -1
    private static var riseMs = -1
    private static var riseCurve = -1
    private static var lightRises = 0
    private static var keyboardShows = 0
    private static var clearScrolls = 0
    private static var clearAt: CFTimeInterval?
    private static var clearFrames = 0
    private static var opens = 0
    #endif

    /// The Text tool was tapped.
    static func begin() {
        observeKeyboard()
        if let interval { signposter.endInterval("TextOpen", interval) }
        start = CACurrentMediaTime()
        interval = signposter.beginAnimationInterval("TextOpen")
        accessoryMs = -1
        toolsVisibleMs = -1
        focusMs = -1
        #if DEBUG
        keyboardMs = -1
        willShowMs = -1
        riseMs = -1
        riseCurve = -1
        lightRises = 0
        keyboardShows = 0
        clearScrolls = 0
        clearAt = nil
        clearFrames = 0
        #endif
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

    /// The board scrolled the block being written clear of the tools.
    static func noteClearScroll() {
        guard start != nil else { return }
        signposter.emitEvent("clearScroll")
        #if DEBUG
        clearScrolls += 1
        clearAt = CACurrentMediaTime()
        clearFrames = 0
        #endif
    }

    // MARK: The page as a session ends

    #if DEBUG
    private static var cardHeight: CGFloat = 0
    private static var exitFrom: CGFloat?
    private static var exitShrink: CGFloat = 0
    #endif

    /// The card holding the page has this height now. Once the session
    /// has ended (not writing) and until the keyboard is gone, how far it
    /// is below its height when the session began (it should hold still).
    static func noteCardHeight(_ height: CGFloat, writing: Bool) {
        #if DEBUG
        if let exitFrom, !writing { exitShrink = max(exitShrink, exitFrom - height) }
        if exitFrom == nil { cardHeight = height }
        #endif
    }

    /// A writing session began on a card of the last noted height.
    static func noteSessionBegan() {
        #if DEBUG
        observeKeyboard()
        exitFrom = cardHeight
        exitShrink = 0
        #endif
    }

    // MARK: The page's way back after a session

    #if DEBUG
    private static var pageOffset: CGFloat?
    private static var endedAt: CFTimeInterval?
    private static var lastOffset: CGFloat?
    private static var lastMoveAt: CFTimeInterval?
    private static var exitMoves = 0
    private static var exitLandMs = -1
    private static var exitTrace: [String] = []
    #endif

    /// A writing session ended at this scroll offset.
    static func noteSessionEnded(offset: CGFloat) {
        #if DEBUG
        endedAt = CACurrentMediaTime()
        lastOffset = offset
        lastMoveAt = nil
        exitMoves = 0
        exitLandMs = -1
        exitTrace = []
        #endif
    }

    /// The page stands at this scroll offset now. For 0.5 s after a
    /// keep-clear scroll: how many frames it moves on (one under Reduce
    /// Motion). For 1.5 s after a session ends: how many separate moves
    /// it makes (a still beat of 80 ms or more parts two), and when it
    /// last moved.
    static func notePageOffset(_ offset: CGFloat) {
        #if DEBUG
        if let clearAt, CACurrentMediaTime() - clearAt < 0.5, offset != pageOffset { clearFrames += 1 }
        pageOffset = offset
        guard let endedAt, let lastOffset, abs(offset - lastOffset) > 0.25 else { return }
        let now = CACurrentMediaTime()
        guard now - endedAt < 1.5 else { return }
        if lastMoveAt.map({ now - $0 >= 0.08 }) ?? true { exitMoves += 1 }
        lastMoveAt = now
        self.lastOffset = offset
        exitLandMs = Int(((now - endedAt) * 1000).rounded())
        exitTrace.append("\(exitLandMs):\(Int(offset.rounded()))")
        #endif
    }

    #if DEBUG
    static var snapshot: [String: Any] {
        ["opens": opens, "ms": keyboardMs, "accessoryMs": accessoryMs, "toolsVisibleMs": toolsVisibleMs,
         "focusMs": focusMs,
         "keyboardMs": keyboardMs, "willShowMs": willShowMs, "riseMs": riseMs, "riseCurve": riseCurve,
         "lightRises": lightRises,
         "keyboardShows": keyboardShows, "clearScrolls": clearScrolls, "clearFrames": clearFrames,
         "exitShrink": Int(exitShrink.rounded()),
         "exitMoves": exitMoves, "exitLandMs": exitLandMs, "exitTrace": exitTrace.joined(separator: " ")]
    }
    #endif

    private static func elapsed() -> Int? {
        guard let start else { return nil }
        return Int(((CACurrentMediaTime() - start) * 1000).rounded())
    }

    private static func observeKeyboard() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
            #if DEBUG
            // The system's own rise: how long, on which curve.
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
            let curve = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
            #endif
            MainActor.assumeIsolated {
                guard start != nil else { return }
                #if DEBUG
                keyboardShows += 1
                if risesLight() { lightRises += 1 }
                if willShowMs < 0, let ms = elapsed() {
                    willShowMs = ms
                    riseMs = Int(((duration ?? -0.001) * 1000).rounded())
                    riseCurve = curve ?? -1
                }
                #endif
                signposter.emitEvent("keyboardWillShow")
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { keyboardLanded() }
        }
        #if DEBUG
        center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { exitFrom = nil }
        }
        #endif
    }

    #if DEBUG
    /// The keyboard now rising is the light one: the field with focus asks
    /// for no dark keyboard and sits in a light trait. It must rise dark,
    /// not be swapped to dark once on its way (#162).
    private static func risesLight() -> Bool {
        let field = UIResponder.currentFirstResponder
        let appearance: UIKeyboardAppearance
        if let view = field as? UITextView {
            appearance = view.keyboardAppearance
        } else if let view = field as? UITextField {
            appearance = view.keyboardAppearance
        } else {
            return false
        }
        switch appearance {
        case .dark: return false
        case .light: return true
        default: return (field as? UIView)?.traitCollection.userInterfaceStyle != .dark
        }
    }
    #endif

    private static func keyboardLanded() {
        guard let interval else { return }
        signposter.endInterval("TextOpen", interval)
        self.interval = nil
        #if DEBUG
        guard let ms = elapsed() else { return }
        keyboardMs = ms
        opens += 1
        log.info("""
            text open ms=\(ms) accessory=\(accessoryMs) focus=\(focusMs) willShow=\(willShowMs) \
            rise=\(riseMs) curve=\(riseCurve) \
            shows=\(keyboardShows) light=\(lightRises) open=\(opens)
            """)
        #endif
    }
}
