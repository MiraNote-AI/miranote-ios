import MiraNoteKit
import SwiftUI
import UIKit

/// One star (#206, fold demo v4). A quick tap shakes the jar. Held, it
/// gathers tension from 120 ms (it lifts and grows, a ring fills round
/// it) and at 350 ms commits: the page opens. Letting go before then, or
/// sliding 10 pt, springs it back silently (`StarHold`). VoiceOver reads
/// it as a button that opens the page at once. It drops in from `drop`
/// when given one (or, under Reduce Motion, fades in).
struct StarButton: View {
    let star: JarStar
    let size: CGFloat
    let rotation: Double
    let drop: CGSize?
    let delay: Double
    let reduceMotion: Bool
    var onShake: () -> Void = {}
    /// The tension began (true) or sprang back (false).
    var onTension: (Bool) -> Void = { _ in }
    /// The hold committed; the star's middle on screen, lifted.
    var onCommit: (CGPoint) -> Void = { _ in }
    /// VoiceOver's activate: the page opens directly.
    let action: () -> Void

    @State private var landed = false
    @State private var hold = StarHold()
    /// The finger is down (a cancelled hold waits for it to lift).
    @State private var touching = false
    @State private var tension: CGFloat = 0
    @State private var timer: Task<Void, Never>?
    @State private var center: CGPoint = .zero

    /// The lift at full tension.
    static let lift: CGFloat = 10
    static let grow: CGFloat = 0.3

    var body: some View {
        let waiting = drop != nil && !landed
        PageStar(memory: star.memory)
            .frame(width: size, height: size)
            // Where it rests, before the hold lifts it.
            .onGeometryChange(for: CGPoint.self) {
                let frame = $0.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { center = $0 }
            .rotationEffect(.degrees(waiting && !reduceMotion ? 0 : rotation))
            .scaleEffect(1 + Self.grow * tension)
            .overlay { ring }
            .offset(y: -Self.lift * tension)
            .frame(width: size * 1.3, height: size * 1.3)
            .contentShape(Circle())
            .gesture(press)
            .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
            .opacity(waiting ? 0 : 1)
            .onAppear {
                guard drop != nil, !landed else { return }
                let motion: Animation = reduceMotion
                    ? .easeOut(duration: 0.4)
                    : .spring(response: 0.55, dampingFraction: 0.68)
                withAnimation(motion.delay(delay)) { landed = true }
            }
            .onDisappear { timer?.cancel() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction(.default, action)
            .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    /// The hold's progress: a white under-stroke, a faint track, and the
    /// filled arc from the top.
    private var ring: some View {
        let diameter = size * 0.45 * 3 * (1 + Self.grow * tension)
        let amber = Color(hex: 0xA8682A)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 5)
            Circle().stroke(amber.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: tension)
                .stroke(amber.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .opacity(tension > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touching {
                    touching = true
                    begin()
                } else if hold.moved(hypot(value.translation.width, value.translation.height)) == .cancel {
                    springBack()
                }
            }
            .onEnded { _ in
                touching = false
                switch hold.up(at: CACurrentMediaTime()) {
                case .shake:
                    timer?.cancel()
                    onShake()
                case .cancel: springBack()
                case .commit: commit()
                case .none: break
                }
            }
    }

    private func begin() {
        let start = CACurrentMediaTime()
        hold.down(at: start)
        timer?.cancel()
        timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(StarHold.tapWindow))
            guard !Task.isCancelled, hold.isPressing else { return }
            onTension(true)
            withAnimation(.linear(duration: StarHold.commitAfter - StarHold.tapWindow)) { tension = 1 }
            try? await Task.sleep(for: .seconds(start + StarHold.commitAfter - CACurrentMediaTime()))
            guard !Task.isCancelled, hold.tick(at: max(CACurrentMediaTime(), start + StarHold.commitAfter)) == .commit
            else { return }
            commit()
        }
    }

    /// Released or slid away during the tension: back, without a sound.
    private func springBack() {
        timer?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tension = 0 }
        onTension(false)
    }

    private func commit() {
        timer?.cancel()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        onCommit(CGPoint(x: center.x, y: center.y - Self.lift))
        // The open draws the star from here on; the button rests unseen.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { tension = 0 }
    }

    private var label: String {
        star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
    }
}
