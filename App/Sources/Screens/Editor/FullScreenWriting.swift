import SwiftUI

/// Full-screen writing (#184): the block being written opened on a page of
/// its own for long text, keyboard up. Cancel leaves the block as it was;
/// Done hands the words back, where each line becomes a block of its own.
struct FullScreenWritingPage: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onDone: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(
                leading: "Cancel",
                trailing: "Done",
                onLeading: onCancel,
                onTrailing: onDone,
                leadingMuted: false,
                leadingID: "fullScreen.cancel",
                trailingID: "fullScreen.done"
            )
            Text("Each line becomes its own block.")
                .font(Sans.font(size: 13, weight: 400))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.chromeInset + 5)
            TextEditor(text: $text)
                .font(Sans.font(size: 18, weight: 400))
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, Metrics.chromeInset)
                .accessibilityIdentifier("fullScreen.editor")
        }
        .screenBackground()
        .onAppear { focused = true }
    }
}
