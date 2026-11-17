import MiraNoteKit
import SwiftUI

/// One star. A tap falls through to the jar, which shakes; held for
/// 350 ms it opens its page (#206). VoiceOver reads it as a button that
/// opens the page. It drops in from `drop` when given one (or, under
/// Reduce Motion, fades in).
struct StarButton: View {
    let star: JarStar
    let size: CGFloat
    let rotation: Double
    let drop: CGSize?
    let delay: Double
    let reduceMotion: Bool
    let action: () -> Void

    @State private var landed = false

    var body: some View {
        let waiting = drop != nil && !landed
        PageStar(memory: star.memory)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(waiting && !reduceMotion ? 0 : rotation))
            .frame(width: size * 1.3, height: size * 1.3)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 10, perform: action)
            .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
            .opacity(waiting ? 0 : 1)
            .onAppear {
                guard drop != nil, !landed else { return }
                let motion: Animation = reduceMotion
                    ? .easeOut(duration: 0.4)
                    : .spring(response: 0.55, dampingFraction: 0.68)
                withAnimation(motion.delay(delay)) { landed = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction(.default, action)
            .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    private var label: String {
        star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
    }
}
