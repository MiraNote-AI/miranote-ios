import MiraNoteKit
import SwiftUI

/// The debug page's words for the scheduler's reasons and outcomes, as
/// catalog keys (app language). Bucket names are trigger content and go
/// through `TriggerContent.zh`.
enum TriggerDebugText {
    static func reason(_ ineligible: Ineligible) -> Text {
        switch ineligible {
        case .tooFewPhotos: return Text("Fewer than 3 photos")
        case .tooRecent: return Text("Under 12 hours since the last photo")
        case .tooOld: return Text("Over 60 days")
        case .lowScore: return Text("Score under 0.40")
        case .pushedDay: return Text("Already pushed that day")
        case .blockedDay: return Text("Day blocked")
        case .bucketCooldown: return Text("In a fewer-like-this pause")
        case .aiRejected: return Text("AI turned it down")
        }
    }

    static func outcome(_ outcome: ScheduleRun.GroupOutcome.Outcome) -> Text {
        switch outcome {
        case .cachedOk: return Text("AI passed (remembered)")
        case .cachedRejected: return Text("AI turned it down (remembered)")
        case .ok: return Text("AI passed")
        case .rejected: return Text("AI turned it down")
        case .error: return Text("AI failed")
        case .left: return Text("Left before the answer")
        }
    }

    /// Why a night is empty: the run's code, or not planned yet.
    static func emptyReason(_ code: String?) -> Text {
        switch code {
        case "noCandidate": return Text("No group passed the rules")
        case "aiError": return Text("The AI failed")
        case "leftBeforeResult": return Text("The app was left before the AI answered")
        case "notificationsOff": return Text("Notifications are off")
        case "photosDenied": return Text("Photo library access is needed")
        case nil: return Text("Not planned yet")
        case let other?: return Text(verbatim: other)
        }
    }

    static func ai(_ status: AIStatus) -> Text {
        switch status {
        case .ok: return Text("AI passed")
        case .rejected(let message): return Text("AI turned it down: \(message)")
        case .notSent: return Text("Not sent to the AI")
        }
    }

    static func bucket(_ bucket: PushBucket) -> String {
        TriggerContent.zh(bucket.catalogKey)
    }

    static func score(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// The six scores and the total, as three lines.
    static func breakdown(_ value: FragmentScore) -> [String] {
        let fmt = score
        return [
            String(appCopy: "Recency \(fmt(value.r)), story \(fmt(value.s)), people \(fmt(value.p))"),
            String(appCopy: "Place \(fmt(value.n)), marks \(fmt(value.u)), looks \(fmt(value.a))"),
            String(appCopy: "Total \(fmt(value.total)) (base \(fmt(value.base)) x \(fmt(value.multiplier)))")
        ]
    }

    /// "11.05 Wed 21:00".
    static func slot(_ day: SchedulerSnapshot.Day) -> String {
        "\(TriggerWords.shortDate(day.slotDay)) \(day.slot.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// "11.05 21:04".
    static func stamp(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%d.%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
