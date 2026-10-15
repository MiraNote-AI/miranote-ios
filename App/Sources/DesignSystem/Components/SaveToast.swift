import SwiftUI

/// The handoff's save receipt (screen 38): a 222 x 38 near-black capsule
/// with a check and "Saved to Files" in Bold 12.5 white; a failed save
/// takes the same capsule in #8C4A3A.
struct SaveToast: View {
    enum Message: Equatable {
        case savedToFiles, savedToPhotos, failed

        var text: String {
            switch self {
            case .savedToFiles: return "Saved to Files"
            case .savedToPhotos: return "Saved to Photos"
            case .failed: return "Couldn't save -- try again"
            }
        }
    }

    let message: Message

    var body: some View {
        // As drawn: the glyph near the leading end, the words centred.
        Text(message.text)
            .font(Sans.font(size: 12.5, weight: 700))
            .lineLimit(1)
            .padding(.horizontal, 44)
            .frame(minWidth: 222, minHeight: 38)
            .overlay(alignment: .leading) {
                Image(systemName: message == .failed ? "exclamationmark" : "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.leading, 22)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .background(
                Capsule()
                    .fill(message == .failed ? Color(hex: 0x8C4A3A) : Color(hex: 0x211F1A))
                    .shadow(color: Color(hex: 0x1F1A14).opacity(0.16), radius: 11, y: 8)
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("export.toast")
            .onAppear { AccessibilityNotification.Announcement(message.text).post() }
    }
}
