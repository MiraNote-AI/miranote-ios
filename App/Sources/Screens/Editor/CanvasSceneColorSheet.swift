import MiraNoteKit
import SwiftUI

// MARK: - Custom color sheet while writing (screens 14 and 20)

extension CanvasScene {
    /// Opens the sheet over the scrim: the keyboard goes down, editing (and
    /// with it the scrim and the live preview) stays.
    func openColorSheet(_ target: ColorRequest.Target) {
        guard let id = editor.editingTextItemID, let item = editor.item(id),
              case .text(let block) = item.content else { return }
        let name: String
        switch target {
        case .text: name = block.colorName
        case .background: name = block.backgroundColorName.isEmpty ? "#8B5962" : block.backgroundColorName
        }
        colorRequest = ColorRequest(target: target, original: item,
                                    initial: RGBColor(Palette.color(named: name)))
        textFocus = nil
    }

    @ViewBuilder var colorSheet: some View {
        if let request = colorRequest {
            CustomColorSheet(
                title: request.target == .text ? "Custom text color" : "Custom text background",
                subtitle: request.target == .text
                    ? "Choose a shade, or sample it from your memory."
                    : "Set the color behind your selected text.",
                initial: request.initial,
                onLiveChange: { previewColor($0.hex, for: request) },
                // The color the sheet shows is the one applied, previewed or
                // not (a background sheet opens on #8B5962 with none set);
                // the block's own color is left as it is named, no step.
                onApply: { color in
                    if let hex = request.applied(color.hex) {
                        previewColor(hex, for: request)
                    } else {
                        dropColorPreview(request)
                    }
                    closeColorSheet(keeping: true)
                },
                onCancel: { closeColorSheet(keeping: false) },
                snapshot: editor.pageSnapshot
            )
            .padding(.horizontal, Metrics.chromeInset)
            .transition(.offset(y: 20).combined(with: .opacity))
        }
    }

    /// Apply keeps the preview as one undo step; cancel (swipe down, a tap
    /// outside) drops it. Either way the keyboard comes back on the row.
    func closeColorSheet(keeping: Bool) {
        guard let request = colorRequest else { return }
        if keeping {
            editor.commitPreview(of: request.original)
        } else {
            dropColorPreview(request)
        }
        withAnimation(.easeOut(duration: 0.2)) { colorRequest = nil }
        refocusEditedText()
    }

    /// Shows `hex` live on the block, without an undo step.
    func previewColor(_ hex: String, for request: ColorRequest) {
        let id = request.original.id
        switch request.target {
        case .text: editor.setTextColorName(itemID: id, to: hex, recordingUndo: false)
        case .background: editor.setTextBackground(itemID: id, to: hex, recordingUndo: false)
        }
    }

    /// Puts back only the color the sheet previewed: words dictated while
    /// it was open stay.
    func dropColorPreview(_ request: ColorRequest) {
        guard previewedColor(request) != nil,
              case .text(let original) = request.original.content else { return }
        previewColor(request.target == .text ? original.colorName : original.backgroundColorName, for: request)
    }

    /// The color the block shows in place of the one it had when the sheet
    /// opened; nil when nothing is previewed.
    func previewedColor(_ request: ColorRequest) -> String? {
        guard case .text(let original) = request.original.content,
              case .text(let now) = editor.item(request.original.id)?.content else { return nil }
        let (was, shown) = request.target == .text
            ? (original.colorName, now.colorName)
            : (original.backgroundColorName, now.backgroundColorName)
        return was == shown ? nil : shown
    }

    /// The keyboard comes back once the sheet has gone (focusing in the
    /// same update as the sheet's removal does not take).
    func refocusEditedText() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if let id = editor.editingTextItemID { textFocus = id }
        }
    }
}
