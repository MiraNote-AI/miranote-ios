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
    let action: () -> Void

    @State private var landed = false

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
