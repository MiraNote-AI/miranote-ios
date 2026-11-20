import Foundation

/// One haptic of a star's fold or open: when (ms), how, how strong.
public struct StarHaptic: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case light, medium, rigid, soft
    }

    public let ms: Double
    public let style: Style
    public let intensity: Double

    public init(_ ms: Double, _ style: Style, _ intensity: Double) {
        self.ms = ms
        self.style = style
        self.intensity = intensity
    }
}

/// A Save's page folding into a star and into the jar (#206, design X).
/// Times are milliseconds from the Save tap.
public enum StarFold {
    /// The bottom half swings back on the middle crease.
    public static let halfFoldEnd = 280.0
    /// The half-page folds up accordion-style onto its band: a strip.
    public static let pleatsEnd = 600.0
    /// The strip ties its first loop.
    public static let tieEnd = 680.0
    /// Five rolls wind the strip into the knot.
    public static let windEnd = 1000.0
    /// The knot is squeezed and puffs into the hero star.
    public static let puffEnd = 1200.0
    /// The star arcs into the jar's mouth and drops onto the pile.
    public static let land = 1440.0
    /// The cap seats; then the jar docks back into its header chip.
    public static let dockStart = 1590.0
    public static let end = 1800.0

    public static let haptics: [StarHaptic] = [
        StarHaptic(0, .light, 1), StarHaptic(270, .rigid, 0.6), StarHaptic(400, .light, 0.4),
        StarHaptic(450, .light, 0.4), StarHaptic(580, .rigid, 0.5), StarHaptic(650, .soft, 0.5),
        StarHaptic(780, .soft, 0.35), StarHaptic(830, .soft, 0.35), StarHaptic(875, .soft, 0.35),
        StarHaptic(920, .soft, 0.35), StarHaptic(1040, .medium, 0.8), StarHaptic(1440, .rigid, 0.7),
        StarHaptic(1560, .light, 0.4), StarHaptic(1780, .soft, 0.3)
    ]

    /// Under Reduce Motion: the page cross-fades to its star (200 ms),
    /// which fades and shrinks into the header jar (300 ms).
    public static let fadeToStar = 200.0
    public static let fadeEnd = 500.0
    public static let fadeHaptics = [StarHaptic(fadeEnd, .soft, 0.6)]

    /// What the fold shows at `ms`.
    public enum Beat: Equatable, Sendable {
        case halfFold, pleats, tie, wind, puff, toss
        /// On the pile: the bounces, the cap seating.
        case landed
        /// The jar goes back into its header chip.
        case dock
        case done
    }

    public static func beat(at ms: Double) -> Beat {
        switch ms {
        case ..<halfFoldEnd: return .halfFold
        case ..<pleatsEnd: return .pleats
        case ..<tieEnd: return .tie
        case ..<windEnd: return .wind
        case ..<puffEnd: return .puff
        case ..<land: return .toss
        case ..<dockStart: return .landed
        case ..<end: return .dock
        default: return .done
        }
    }

    /// What a Save shows on Home.
    public enum Arrival: Equatable, Sendable {
        /// Nothing: the page was a star already, or was not saved.
        case none
        /// The fold, the drop into the jar and its dock.
        case fold
        /// Under Reduce Motion: the page cross-fades to its star, which
        /// fades into the header jar.
        case fade
    }

    /// Only the Save that first makes a page a star -- a new page, or a
    /// draft never saved -- and only onto Home, where the jar is.
    public static func arrival(saved: Bool, wasStar: Bool, onHome: Bool, reduceMotion: Bool) -> Arrival {
        guard saved, !wasStar, onHome else { return .none }
        return reduceMotion ? .fade : .fold
    }
}

/// A held star opening its page (#206, design X). Times are milliseconds
/// from the commit, 350 ms into the hold.
public enum StarUnfold {
    /// The cap unscrews and lifts away; the ring releases.
    public static let capEnd = 150.0
    /// The star rises out of the mouth to hero size.
    public static let liftEnd = 400.0
    /// It relaxes back into the knot.
    public static let unpuffEnd = 490.0
    /// The knot rolls back out into the strip and unties.
    public static let unwindEnd = 840.0
    /// The pleats swing back out of the strip.
    public static let pleatsEnd = 990.0
    /// The half with the title and text unfolds last.
    public static let halfEnd = 1140.0
    /// The card grows into the reading page.
    public static let fillEnd = 1390.0
    /// Readable: the reading page takes over.
    public static let end = 1400.0

    public static let haptics: [StarHaptic] = [
        StarHaptic(0, .medium, 0.8), StarHaptic(110, .light, 0.4), StarHaptic(930, .soft, 0.4),
        StarHaptic(1000, .soft, 0.4), StarHaptic(1130, .rigid, 0.4), StarHaptic(end, .soft, 0.4)
    ]

    /// Under Reduce Motion the star cross-fades to the reading page.
    public static let fade = 400.0

    /// What the open shows at `ms` after the commit.
    public enum Beat: Equatable, Sendable {
        case cap, lift, unpuff, unwind, pleats, half, fill
        /// Readable: the page itself is up.
        case open
    }

    public static func beat(at ms: Double) -> Beat {
        switch ms {
        case ..<capEnd: return .cap
        case ..<liftEnd: return .lift
        case ..<unpuffEnd: return .unpuff
        case ..<unwindEnd: return .unwind
        case ..<pleatsEnd: return .pleats
        case ..<halfEnd: return .half
        case ..<end: return .fill
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
