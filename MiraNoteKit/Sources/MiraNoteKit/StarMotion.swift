import Foundation

/// A Save's star on its way to the jar (#206, fold demo v4). Times are
/// milliseconds from the Save tap.
public enum StarFold {
    /// The page shrinks to `pageScale` and lifts.
    public static let shrinkEnd = 180.0
    /// The strip is cut, lifts and turns level.
    public static let cutEnd = 400.0
    /// The strip winds into a pentagon knot.
    public static let windEnd = 780.0
    /// The knot is pinched and puffed into the hero star.
    public static let pinchEnd = 920.0
    /// The star is thrown at the header jar (overlapping the pinch).
    public static let throwStart = 880.0
    /// It lands: the jar squashes, glows and rings.
    public static let land = 1320.0
    public static let end = 1620.0
    /// Haptics of the fold itself; the landing's is the jar's own.
    public static let haptics = [0.0, 840.0]
    /// The page's scale on stage while it folds.
    public static let pageScale = 0.6
    /// The jar circle swells a little just before the star drops in.
    public static let swell = 140.0

    /// What the fold shows at `ms`.
    public enum Beat: Equatable, Sendable {
        case shrink, cut, wind, pinch, `throw`
        /// In the jar: the star rests over the circle a moment, then goes in.
        case landed
        case done
    }

    public static func beat(at ms: Double) -> Beat {
        switch ms {
        case ..<shrinkEnd: return .shrink
        case ..<cutEnd: return .cut
        case ..<windEnd: return .wind
        case ..<throwStart: return .pinch
        case ..<land: return .throw
        case ..<end: return .landed
        default: return .done
        }
    }

    /// What a Save shows on Home.
    public enum Arrival: Equatable, Sendable {
        /// Nothing: the page was a star already, or was not saved.
        case none
        /// The fold, the throw and the landing.
        case fold
        /// Under Reduce Motion: the cover slides away and the jar glows.
        case glow
    }

    /// Only the Save that first makes a page a star -- a new page, or a
    /// draft never saved -- and only onto Home, where the jar is.
    public static func arrival(saved: Bool, wasStar: Bool, onHome: Bool, reduceMotion: Bool) -> Arrival {
        guard saved, !wasStar, onHome else { return .none }
        return reduceMotion ? .glow : .fold
    }
}

/// A held star opening its page (#206, fold demo v4). Times are
/// milliseconds from the commit, 350 ms into the hold.
public enum StarUnfold {
    /// The star rises to the middle, at hero size.
    public static let riseEnd = 210.0
    /// The reversed wind unwinds the strip, tilting it to its cut.
    public static let unwindEnd = 470.0
    /// The strip docks onto a faint page at its true place.
    public static let dockEnd = 630.0
    /// The page unrolls from the strip; then it opens.
    public static let unrollEnd = 770.0
    public static let haptics = [0.0, 470.0]
    /// Under Reduce Motion the page cross-fades in instead.
    public static let fade = 200.0

    /// What the open shows at `ms` after the commit.
    public enum Beat: Equatable, Sendable {
        case rise, unwind, dock, unroll
        /// The page has unrolled: it opens.
        case open
    }

    public static func beat(at ms: Double) -> Beat {
        switch ms {
        case ..<riseEnd: return .rise
        case ..<unwindEnd: return .unwind
        case ..<dockEnd: return .dock
        case ..<unrollEnd: return .unroll
        default: return .open
        }
    }
}

/// A press on a jar star (#206): a quick tap shakes the jar, a 350 ms
/// hold opens the page. Between 120 and 350 ms the star gathers tension;
/// letting go then, or sliding 10 pt, springs it back silently.
public struct StarHold: Equatable, Sendable {
    public static let tapWindow = 0.12
    public static let commitAfter = 0.35
    public static let slop = 10.0

    public enum Outcome: Equatable, Sendable {
        case none
        case shake
        case cancel
        case commit
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case pressing(since: TimeInterval)
        case done
    }

    private var phase = Phase.idle

    public init() {}

    public var isPressing: Bool {
        if case .pressing = phase { return true }
        return false
    }

    public mutating func down(at time: TimeInterval) {
        phase = .pressing(since: time)
    }

    /// The finger moved `distance` points from where it went down.
    public mutating func moved(_ distance: Double) -> Outcome {
        guard isPressing, distance > Self.slop else { return .none }
        phase = .done
        return .cancel
    }

    /// The clock reached `time` with the finger still down.
    public mutating func tick(at time: TimeInterval) -> Outcome {
        guard case .pressing(let since) = phase, time - since >= Self.commitAfter else { return .none }
        phase = .done
        return .commit
    }

    public mutating func up(at time: TimeInterval) -> Outcome {
        guard case .pressing(let since) = phase else {
            phase = .idle
            return .none
        }
        phase = .idle
        let held = time - since
        if held < Self.tapWindow { return .shake }
        return held >= Self.commitAfter ? .commit : .cancel
    }

    /// The press was taken away without a release (the system cancelled
    /// the gesture: a scroll, a call, the app leaving): no shake, no open.
    /// True when a hold was still gathering and must spring back.
    public mutating func reset() -> Bool {
        let wasPressing = isPressing
        phase = .idle
        return wasPressing
    }

    /// The tension, 0 before the tap window closes, 1 at the commit.
    public static func tension(held: TimeInterval) -> Double {
        min(1, max(0, (held - tapWindow) / (commitAfter - tapWindow)))
    }
}
