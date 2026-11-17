import MiraNoteKit
import SwiftUI

/// Where Home's star jar circle sits, for a saved page's star to land on.
struct JarAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

/// A just-saved page's star on its way into the jar (#160): it rises from
/// the foot of Home and arcs into the jar circle, shrinking as it goes.
/// Only drawn, never read by VoiceOver: the jar's own landing says it.
struct FlyingStar: View, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    /// The page whose star flies: its own face (`PageStar`).
    let memory: Memory?

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // Fades into the circle over the last stretch.
        let fade: Double = progress < 0.85 ? 1 : Double((1 - progress) / 0.15)
        let turn: Double = Double(progress) * 144
        Group {
            if let memory { PageStar(memory: memory) } else { StarMark(color: StarMark.paper) }
        }
            .frame(width: 30, height: 30)
            .scaleEffect(1 - 0.45 * progress)
            .rotationEffect(.degrees(turn))
            .opacity(fade)
            .position(point(at: progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A quadratic arc: straight up first, then over to the jar.
    private func point(at t: CGFloat) -> CGPoint {
        let control = CGPoint(x: start.x, y: end.y)
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }
}

/// The jar circle taking a star in: a small bounce, or under Reduce
/// Motion only a warm glow. `beat` counts the landings.
struct JarLanding: ViewModifier {
    let beat: Int
    let reduceMotion: Bool

    private static let glow = Color(hex: 0xE8B04B)

    private struct Pose {
        var scale: CGFloat = 1
        var glow: Double = 0
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Pose(), trigger: beat) { view, pose in
                view
                    .background(Circle().fill(Self.glow).blur(radius: 6).opacity(pose.glow))
                    .scaleEffect(pose.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    if reduceMotion {
                        LinearKeyframe(1, duration: 0.01)
                    } else {
                        SpringKeyframe(1.15, duration: 0.16)
                        SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                    }
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(reduceMotion ? 0.8 : 0.5, duration: 0.15)
                    LinearKeyframe(0, duration: 0.6)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: beat)
    }
}
