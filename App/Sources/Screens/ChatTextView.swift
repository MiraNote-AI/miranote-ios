import SwiftUI
import UIKit

/// The chat composer's field, WeChat's way (owner decision): it grows with
/// the message from one line to four, then scrolls; the keyboard's Send key
/// sends and leaves the keyboard up for the next message; a paste -- new
/// lines and all -- never sends, and Shift+Return on a hardware keyboard
/// puts a new line in (ChatReturn). A UITextView: SwiftUI's multi-line
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
        let view = ChatInputView()
        view.delegate = context.coordinator
        view.font = font
        view.textColor = UIColor(Palette.ink)
        view.tintColor = UIColor(Palette.forest)
        view.backgroundColor = .clear
        // The Send key is on without words too: a staged photo goes alone.
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
            // Not inside the view update: focus changes send their own. By
            // then both may have moved on (the keyboard came back, "+" took
            // it away): act on what they are then, not on this update's.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                let wanted = coordinator.parent.isFocused
                guard wanted != view.isFirstResponder else { return }
                if wanted { view.becomeFirstResponder() } else { view.resignFirstResponder() }
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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // Return while composing (a keyboard's marked text) commits it;
            // dictation's "new line" and a paste or Shift+Return are words.
            let insertingWords = (textView as? ChatInputView)?.takeInsertingWords() == true
            let fromReturnKey = !insertingWords && textView.markedTextRange == nil
                && textView.textInputMode?.primaryLanguage != "dictation"
            guard ChatReturn.sends(replacing: range, with: text, in: textView.text,
                                   fromReturnKey: fromReturnKey) else { return true }
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

/// The field's text view: it knows when a new line is words being put in
/// (a paste, Shift+Return) rather than the Return key.
final class ChatInputView: UITextView {
    private var insertingNewLine = false
    /// A paste was asked for and its words have not come in yet: the
    /// pasteboard is read asynchronously, after paste(_:) returns.
    private var pasting = false

    /// Whether the change being made is words put in, not the Return key.
    /// A paste counts for the first change after it.
    func takeInsertingWords() -> Bool {
        defer { pasting = false }
        return insertingNewLine || pasting
    }

    override func paste(_ sender: Any?) {
        pasting = true
        super.paste(sender)
    }

    override var keyCommands: [UIKeyCommand]? {
        let newLine = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertNewLine))
        newLine.wantsPriorityOverSystemBehavior = true
        return [newLine] + (super.keyCommands ?? [])
    }

    @objc private func insertNewLine() {
        insertingNewLine = true
        defer { insertingNewLine = false }
        insertText("\n")
        // A programmatic insert is not reported as a change by every iOS.
        delegate?.textViewDidChange?(self)
    }
}

/// When the chat field sends: the keyboard's Return key typed at the end of
/// the field, nothing selected -- a blank field too: a staged photo goes
/// out on its own, and with nothing staged the send is a no-op. A new line
/// from anywhere else -- a paste, Shift+Return, a keyboard's marked text,
/// dictation's "new line" -- is words (`fromReturnKey` false), and so is
/// Return inside the words.
enum ChatReturn {
    static func sends(replacing range: NSRange, with replacement: String, in text: String,
                      fromReturnKey: Bool) -> Bool {
        fromReturnKey && replacement == "\n" && range.length == 0
            && range.location == (text as NSString).length
    }
}
