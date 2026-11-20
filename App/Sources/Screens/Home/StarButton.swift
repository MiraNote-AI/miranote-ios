import MiraNoteKit
import SwiftUI
import UIKit

/// One star (#206, design X). A quick tap shakes the jar. Held, it
/// presses in, gathers tension from 120 ms (a green ring fills round it)
/// and at 350 ms commits: the page opens. Letting go before then, or
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
    /// The hold committed; the star's middle on screen.
    var onCommit: (CGPoint) -> Void = { _ in }
    /// VoiceOver's activate: the page opens directly.
    let action: () -> Void

    @State private var landed = false
    @State private var hold = StarHold()
    /// The finger is on it: it presses in a little.
    @State private var pressing = false
    /// The finger is down (a cancelled hold waits for it to lift).
    @State private var touching = false
    /// Resets when the press ends or the system cancels it: a cancel
    /// never reaches `onEnded`.
    @GestureState private var pressed = false
    @State private var tension: CGFloat = 0
    @State private var timer: Task<Void, Never>?
    @State private var center: CGPoint = .zero

    /// How far a held star presses in.
    static let press: CGFloat = 0.93
    /// The hold's ring: the app's green.
    static let ring = Color(hex: 0x2F4A3A)

    var body: some View {
        let waiting = drop != nil && !landed
        // Turned under a light that stays top left.
        PageStar(memory: star.memory, rotation: waiting && !reduceMotion ? 0 : rotation)
            .frame(width: size, height: size)
            // Where it rests, before the hold lifts it.
            .onGeometryChange(for: CGPoint.self) {
                let frame = $0.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { center = $0 }
            // Under Reduce Motion the ring alone shows the hold.
            .scaleEffect(pressing && !reduceMotion ? Self.press : 1)
            .overlay { ring }
            .frame(width: size * 1.3, height: size * 1.3)
            .contentShape(Circle())
            .gesture(press)
            .onChange(of: pressed) { _, down in
                guard !down else { return }
                touching = false
                // Cancelled, not released: the hold must not open later.
                if hold.reset() { springBack() }
            }
            .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
            .opacity(waiting ? 0 : 1)
            .onAppear {
                guard drop != nil, !landed else { return }
                let motion: Animation = reduceMotion
                    ? .easeOut(duration: 0.4)
                    : .spring(response: 0.55, dampingFraction: 0.68)
                withAnimation(motion.delay(delay)) { landed = true }
            }
            .onDisappear {
                timer?.cancel()
                touching = false
                _ = hold.reset()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction(.default, action)
            .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    /// The hold's progress: a faint white disc, a faint green track, and
    /// the green arc filling from the top.
    private var ring: some View {
        let radius = size * 0.45 * 1.6
        return ZStack {
            Circle().fill(Color.white.opacity(0.26)).padding(4)
            Circle().stroke(Self.ring.opacity(0.16), lineWidth: 3)
            Circle().trim(from: 0, to: tension)
                .stroke(Self.ring, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 2 * radius, height: 2 * radius)
        .opacity(tension > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressed) { _, pressed, _ in pressed = true }
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
                    release()
                    onShake()
                case .cancel: springBack()
                case .commit: commit()
                case .none: break
                }
            }
    }

    private func begin() {
        withAnimation(.easeOut(duration: StarHold.tapWindow)) { pressing = true }
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tension = 0
            pressing = false
        }
        onTension(false)
    }

    private func release() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pressing = false }
    }

    private func commit() {
        timer?.cancel()
        if let haptic = StarUnfold.haptics.first {
            UIImpactFeedbackGenerator(style: haptic.style.impact).impactOccurred(intensity: haptic.intensity)
        }
        onCommit(center)
        // The open draws the star from here on; the button rests unseen.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            tension = 0
            pressing = false
        }
    }

    private var label: String {
        star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
    }
}

extension StarHaptic.Style {
    var impact: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .rigid: return .rigid
        case .soft: return .soft
        }
    }
}
