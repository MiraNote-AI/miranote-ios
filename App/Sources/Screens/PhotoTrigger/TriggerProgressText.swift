import MiraNoteKit
import SwiftUI

/// One progress step as the debug entry words it (handoff 7.5), in the app
/// language. The backend's own messages are shown as they come.
struct TriggerProgressText: View {
    let step: TriggerProgress

    var body: some View {
        text
            .font(.miraCaption)
            .foregroundStyle(isFailure ? Palette.ink : Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isFailure: Bool {
        switch step {
        case .failed, .allFailed: return true
        default: return false
        }
    }

    private var text: Text {
        switch step {
        case .preparing:
            return Text("Preparing...")
        case .partialLibrary:
            return Text("Only some photos are visible")
        case .analyzing(let done, let total):
            return Text("Looking at photos \(done)/\(total)...")
        case .askingAI(let rank, let date, let place, let count):
            if let place {
                return Text("Asking the AI... (rank \(rank): \(date) \(place), \(count) photos)")
            }
            return Text("Asking the AI... (rank \(rank): \(date), \(count) photos)")
        case .wrapped:
            return Text("That was the last group, starting from the top")
        case .rejected(let rank, let message, let next):
            // The backend's Chinese message has no entry and shows as sent;
            // the app's own ("too few photos could be read") is translated.
            let reason = String(appCopy: LocalizedStringResource(String.LocalizationValue(message)))
            return Text("Rank \(rank) did not pass (\(reason)), trying rank \(next)...")
        case .scheduled(let rank, let score):
            let shown = String(format: "%.2f", score)
            return Text("Scheduled, the push comes in 10 s (rank \(rank), score \(shown))")
        case .allFailed(let tried) where tried == TriggerRun.maxTries:
            return Text("Tried 3 groups and none passed. You can press \"Try a group outside the schedule\" again")
        case .allFailed(let tried):
            // swiftlint:disable:next line_length
            return Text("Tried \(tried) groups and none passed. You can press \"Try a group outside the schedule\" again")
        case .failed(let failure):
            return Self.text(for: failure)
        }
    }

    static func text(for failure: TriggerFailure) -> Text {
        switch failure {
        case .backendUnreachable: return Text("Cannot reach the backend")
        case .aiTimeout: return Text("AI timeout")
        case .noFragment: return Text("No suitable group in the last 60 days")
        case .notificationsOff: return Text("Notifications are off")
        case .photosDenied: return Text("Photo library access is needed")
        case .unauthorized: return Text("This build has no beta access")
        case .backend(let message): return Text("The backend said: \(message)")
        }
    }
}
