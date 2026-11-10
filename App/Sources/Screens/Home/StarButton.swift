import MiraNoteKit
import SwiftUI

/// One star: a tap opens its page. It drops in from `drop` when given one
/// (or, under Reduce Motion, fades in), and its mood tints it with a short
/// cross-fade when the mood arrives.
struct StarButton: View {
    let star: JarStar
    let size: CGFloat
    let rotation: Double
    let drop: CGSize?
    let delay: Double
    let reduceMotion: Bool
    /// The jar's shakes: each one jostles the star and makes it twinkle.
    let shakes: Int
    let action: () -> Void

    @State private var landed = false

    /// Which way and how far this star jostles, from its own tilt so
    /// neighbors move apart rather than as one block.
    private var jostle: CGSize {
        let side = sin(rotation * .pi / 37)
        return CGSize(width: 5 * side, height: -4 - 3 * abs(side))
    }

    var body: some View {
        let waiting = drop != nil && !landed
        Button(action: action) {
            StarMark(color: Palette.mood(star.memory.mood))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(waiting && !reduceMotion ? 0 : rotation))
                .frame(width: size * 1.3, height: size * 1.3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
        .opacity(waiting ? 0 : 1)
        .keyframeAnimator(initialValue: CGSize.zero, trigger: shakes) { content, offset in
            content.offset(offset)
        } keyframes: { _ in
            KeyframeTrack {
                if reduceMotion {
                    LinearKeyframe(CGSize.zero, duration: 0.01)
                } else {
                    SpringKeyframe(CGSize(width: -jostle.width, height: jostle.height), duration: 0.12)
                    SpringKeyframe(CGSize(width: jostle.width, height: 0), duration: 0.14)
                    SpringKeyframe(CGSize.zero, duration: 0.3, spring: .bouncy)
                }
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: shakes) { content, glow in
            content.brightness(glow)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.22, duration: 0.15)
                LinearKeyframe(0, duration: 0.45)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: star.memory.mood)
        .onAppear {
            guard drop != nil, !landed else { return }
            let motion: Animation = reduceMotion
                ? .easeOut(duration: 0.4)
                : .spring(response: 0.55, dampingFraction: 0.68)
            withAnimation(motion.delay(delay)) { landed = true }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    private var accessibilityText: String {
        let title = star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
        return String(appCopy: "\(title), \(star.memory.mood?.displayName ?? String(appCopy: "mood not read yet"))")
    }
}
