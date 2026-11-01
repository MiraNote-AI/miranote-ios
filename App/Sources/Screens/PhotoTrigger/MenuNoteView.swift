import SwiftUI

/// What the story's "..." menu answers (handoff 7.7). Phase 1 only says
/// it; the ranking does not change yet.
enum MenuNote: Equatable {
    case fewerLikeThis
    case notThisDay

    /// How long the note stays.
    static let duration: TimeInterval = 2
}

/// The menu's answer in small type at the foot of the screen.
struct MenuNoteView: View {
    let note: MenuNote
    /// The push bucket's name, Chinese content from the memory.
    let bucket: String
    let bottom: CGFloat

    var body: some View {
        text
            .font(.miraCaption)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(.bottom, bottom + 28)
            .padding(.horizontal, 24)
            .transition(.opacity)
            .accessibilityIdentifier("trigger.menuNote")
    }

    private var text: Text {
        switch note {
        case .fewerLikeThis: return Text("Fewer like \"\(bucket)\" from now on")
        case .notThisDay: return Text("This day won't be pushed again")
        }
    }
}
