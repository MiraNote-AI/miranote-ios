import Foundation

/// One finger on the story (`PhotoTriggerView`): going down pauses; the
/// lift is a tap (the left third back, the rest forward), a sideways swipe,
/// or the end of a hold, which resumes. A touch the system takes away --
/// a call, Control Center, the app leaving -- never lifts: it ends as a
/// hold does, or the story would stay paused.
struct StoryTouch {
    enum Outcome: Equatable {
        case forward, back, resume
    }

    /// A held finger that has not moved is a pause, not a tap, after this.
    static let tapLimit: TimeInterval = 0.25
    static let swipeDistance: CGFloat = 50

    /// When the finger now on the story went down; nil when none is.
    private var downAt: Date?

    /// The finger went down or moved: true the first time (pause).
    mutating func down(at date: Date) -> Bool {
        guard downAt == nil else { return false }
        downAt = date
        return true
    }

    /// The finger lifted at `liftX` of a story `width` wide; nil when no
    /// touch was on (one already taken away).
    mutating func lift(at date: Date, translation: CGSize, liftX: CGFloat, width: CGFloat) -> Outcome? {
        guard let start = downAt else { return nil }
        downAt = nil
        let held = date.timeIntervalSince(start)
        let dx = translation.width
        let dy = translation.height
        if abs(dx) > Self.swipeDistance, abs(dx) > abs(dy) { return dx < 0 ? .forward : .back }
        if held < Self.tapLimit, abs(dx) < 10, abs(dy) < 10 { return liftX < width / 3 ? .back : .forward }
        return .resume
    }

    /// The touch was taken away without a lift: `.resume` if one was on.
    mutating func cancel() -> Outcome? {
        guard downAt != nil else { return nil }
        downAt = nil
        return .resume
    }
}
