import SwiftUI
import UIKit

/// The chat composer's field, WeChat's way (owner decision): it grows with
/// the message from one line to four, then scrolls; the keyboard's Send key
/// sends and leaves the keyboard up for the next message; a paste -- new
/// lines and all -- never sends. A UITextView: SwiftUI's multi-line
/// TextField cannot tell the Return key from a pasted new line, and its
/// single-line one lowers the keyboard on every send.
struct ChatTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: UIFont
    let onSend: () -> Void

    static let minHeight: CGFloat = 34
    private static let maxLines: CGFloat = 4

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = font
        view.textColor = UIColor(Palette.ink)
        view.tintColor = UIColor(Palette.forest)
        view.backgroundColor = .clear
        view.returnKeyType = .send
        view.textContainer.lineFragmentPadding = 0
        // One line sits centred in the 34 pt row, as the single-line field did.
        let inset = max(0, (Self.minHeight - font.lineHeight) / 2)
        view.textContainerInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "Message Mira"
        view.accessibilityIdentifier = "chat.field"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if isFocused != view.isFirstResponder {
            // Not inside the view update: focus changes send their own.
            DispatchQueue.main.async {
                if isFocused { view.becomeFirstResponder() } else { view.resignFirstResponder() }
            }
        }
    }

    /// The words' height, one line to four; past four the view scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let insets = uiView.textContainerInset.top + uiView.textContainerInset.bottom
        let cap = ceil(font.lineHeight * Self.maxLines + insets)
        return CGSize(width: width, height: min(max(fitting, Self.minHeight), cap))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatTextView

        init(_ parent: ChatTextView) {
            self.parent = parent
        }

        /// The Return key arrives as a change of exactly one new line; a
        /// paste arrives as one change carrying its other words too.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // Return while composing (a keyboard's marked text) commits it.
            guard text == "\n", textView.markedTextRange == nil else { return true }
            parent.onSend()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
