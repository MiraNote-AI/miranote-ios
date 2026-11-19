import MiraNoteKit
import SwiftUI

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

/// The jar circle taking a star in (fold demo v4): a squash and settle,
/// a warm glow and one ring going out, or under Reduce Motion only the
/// glow. `beat` counts the landings.
struct JarLanding: ViewModifier {
    let beat: Int
    /// The star is about to drop in: the circle swells a little for it.
    var swell = false
    let reduceMotion: Bool

    private static let glow = Color(hex: 0xE8B04B)
    private static let ring = Color(hex: 0xC88C3C)

    private struct Pose {
        var scale: CGFloat = 1
        var glow: Double = 0
        /// The ring's spread, 0...1; it fades as it goes.
        var ring: CGFloat = 1
    }

    func body(content: Content) -> some View {
        // Read here: the animator's closure is Sendable and may not read a
        // main-actor static.
        let glow = Self.glow, ring = Self.ring, swelled: CGFloat = swell ? 1.06 : 1
        return content
            .keyframeAnimator(initialValue: Pose(), trigger: beat) { view, pose in
                view
                    .background(Circle().fill(glow).blur(radius: 10).opacity(pose.glow))
                    .scaleEffect(pose.scale * swelled)
                    .overlay {
                        // 22 to 40 pt out from a 44 pt circle.
                        Circle()
                            .stroke(ring.opacity(0.7 * (1 - pose.ring)), lineWidth: 2.4)
                            .frame(width: 44 + 36 * pose.ring, height: 44 + 36 * pose.ring)
                            .allowsHitTesting(false)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    if reduceMotion {
                        LinearKeyframe(1, duration: 0.01)
                    } else {
                        CubicKeyframe(0.84, duration: 0.07)
                        CubicKeyframe(1.08, duration: 0.09)
                        CubicKeyframe(0.97, duration: 0.07)
                        SpringKeyframe(1, duration: 0.2, spring: .bouncy)
                    }
                }
                KeyframeTrack(\.glow) {
                    if reduceMotion {
                        LinearKeyframe(0.8, duration: 0.15)
                        LinearKeyframe(0, duration: 0.6)
                    } else {
                        LinearKeyframe(1, duration: 0.02)
                        CubicKeyframe(0, duration: 0.35)
                    }
                }
                KeyframeTrack(\.ring) {
                    if reduceMotion {
                        LinearKeyframe(1, duration: 0.01)
                    } else {
                        LinearKeyframe(0, duration: 0.01)
                        CubicKeyframe(1, duration: 0.26)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: beat)
    }
}

extension View {
    /// The page opened from the star jar zooms out of `id`'s source on
    /// iOS 18; iOS 17 pushes as always.
    @ViewBuilder
    func zoomTransition(from id: some Hashable, in namespace: Namespace.ID, when enabled: Bool) -> some View {
        if #available(iOS 18.0, *), enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// The zoom's source: the page where the star unrolled it.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
