import MiraNoteKit
import SwiftUI

/// Dims-and-pulses an element while Mira works on it, and blocks touches so
/// the work cannot be disturbed -- everything else stays interactive.
struct BreathingLock: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.45 : 1)
            .allowsHitTesting(!active)
            .onChange(of: active) { _, nowActive in
                if nowActive {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        dimmed = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dimmed = false }
                }
            }
    }
}

/// An element's on-screen geometry once in-flight gesture deltas apply.
struct ElementGeometry {
    let position: CGPoint
    let size: CGSize
    let rotation: Double
}

/// In-flight gesture values (see the @GestureState notes above).
struct ActiveMove {
    let itemID: CanvasItem.ID
    let translation: CGSize
}

struct ActiveResize {
    let itemID: CanvasItem.ID
    let corner: HandleCorner
    let translation: CGSize
}

struct ActiveRotation {
    let itemID: CanvasItem.ID
    let degrees: Double
}

/// Which corner a resize handle sits on; `sign` maps drag translation to
/// size growth for that corner.
enum HandleCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var sign: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeading: return (-1, -1)
        case .topTrailing: return (1, -1)
        case .bottomLeading: return (-1, 1)
        case .bottomTrailing: return (1, 1)
        }
    }
}
