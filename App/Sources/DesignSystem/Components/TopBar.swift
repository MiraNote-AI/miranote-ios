import SwiftUI

/// Editor top bar (v2.1): leading back chip | center title, or an undo icon
/// when the scene has no title (the canvas) | trailing ink "Done" pill.
/// The center stays optically centered regardless of the side widths.
struct TopBar: View {
    var leading: String?
    var leadingSymbol: String?
    var title: String = ""
    var trailing: String? = "Done"
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}
    /// When set and `title` is empty, a centered undo icon replaces the title.
    var onUndo: (() -> Void)?
    /// Dims and disables the undo icon when there is nothing to undo.
    var undoEnabled = true

    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
            } else if let onUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Palette.paper)
                                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!undoEnabled)
                .opacity(undoEnabled ? 1 : 0.35)
                .accessibilityLabel("Undo")
                .accessibilityIdentifier("editor.undo")
            }

            HStack {
                if let leading {
                    Button(action: onLeading) {
                        HStack(spacing: 5) {
                            if let leadingSymbol {
                                Image(systemName: leadingSymbol)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(leading)
                        }
                    }
                    .buttonStyle(SoftPill())
                }

                Spacer()

                if let trailing {
                    Button(trailing, action: onTrailing)
                        .buttonStyle(PrimaryPill(horizontalPadding: 18, verticalPadding: 8))
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }
}
