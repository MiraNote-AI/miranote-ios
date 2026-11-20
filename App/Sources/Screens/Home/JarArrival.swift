import MiraNoteKit
import SwiftUI
import UIKit

/// Where Home's star jar circle sits, for a saved page's star to land on.
struct JarAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

/// Reduce Motion, or `-REDUCE_MOTION` standing in for it in UI tests.
enum ReduceMotion {
    static func resolved(_ system: Bool) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-REDUCE_MOTION") { return true }
        #endif
        return system
    }
}

/// The fold's and the open's clock. `-STAR_SLOW <n>` (debug builds)
/// plays them n times slower, to film them frame by frame.
enum StarClock {
    static let rate: Double = {
        #if DEBUG
        let slow = UserDefaults.standard.double(forKey: "STAR_SLOW")
        if slow > 0 { return slow }
        #endif
        return 1
    }()

    /// Milliseconds of the timeline since `start`.
    static func ms(since start: Date, at date: Date = .now) -> Double {
        date.timeIntervalSince(start) * 1000 / rate
    }

    /// Sleeps until `ms` of the timeline that started at `start`.
    static func sleep(until ms: Double, from start: Date) async throws {
        let left = (ms - Self.ms(since: start)) / 1000 * rate
        if left > 0 { try await Task.sleep(for: .seconds(left)) }
    }
}

/// Plays a fold's haptics (`StarHaptic`), one prepared generator a style.
@MainActor
final class StarHaptics {
    private let generators: [StarHaptic.Style: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light), .medium: UIImpactFeedbackGenerator(style: .medium),
        .rigid: UIImpactFeedbackGenerator(style: .rigid), .soft: UIImpactFeedbackGenerator(style: .soft)
    ]

    init() {
        generators.values.forEach { $0.prepare() }
    }

    func play(_ haptic: StarHaptic) {
        generators[haptic.style]?.impactOccurred(intensity: haptic.intensity)
    }
}
