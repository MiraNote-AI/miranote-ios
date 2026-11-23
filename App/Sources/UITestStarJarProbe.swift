#if DEBUG
import Foundation
import SwiftUI

/// -UITEST probes for the star jar (#243), read through `DebugStateProbe`:
/// the Reduce Motion fade's star, which fades where it is, and the stars
/// Home's header jar shows dressed.
enum StarJarProbe {
    private struct Sighting {
        let start: Date
        let point: CGPoint
        let radius: CGFloat
    }

    // Set and read on the main thread (the fold's and the header jar's
    // canvases); a test probe, not state.
    /// Frames the fade drew its star in, and how far the star moved and
    /// how much its radius changed since the first of them.
    nonisolated(unsafe) private static var fadeFrames = 0
    nonisolated(unsafe) private static var fadeTravel: CGFloat = 0
    nonisolated(unsafe) private static var fadeResize: CGFloat = 0
    nonisolated(unsafe) private static var fadeFirst: Sighting?
    /// The header jar as last drawn: its stars, and those in their page's
    /// dress (the others are plain paper).
    nonisolated(unsafe) private static var headerStars = 0
    nonisolated(unsafe) private static var headerDressed = 0

    /// The fade that started at `start` drew its star at `point`.
    static func fadeStar(_ start: Date, at point: CGPoint, radius: CGFloat) {
        guard let first = fadeFirst, first.start == start else {
            fadeFirst = Sighting(start: start, point: point, radius: radius)
            (fadeFrames, fadeTravel, fadeResize) = (1, 0, 0)
            return
        }
        fadeFrames += 1
        fadeTravel = max(fadeTravel, hypot(point.x - first.point.x, point.y - first.point.y))
        fadeResize = max(fadeResize, abs(radius - first.radius))
    }

    /// The header jar drew `pile`.
    static func header(_ pile: JarPile) {
        headerStars = pile.stars.count
        headerDressed = pile.stars.filter { star in
            if case .baked = star.dress { return true }
            return false
        }.count
    }

    static func add(to state: inout [String: Any]) {
        state["headerStars"] = headerStars
        state["headerDressed"] = headerDressed
        state["fadeFrames"] = fadeFrames
        state["fadeTravel"] = (Double(fadeTravel) * 10).rounded() / 10
        state["fadeResize"] = (Double(fadeResize) * 10).rounded() / 10
    }
}
#endif
