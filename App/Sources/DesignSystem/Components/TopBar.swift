import SwiftUI

/// Editor top bar (2026-10-07 handoff): a frosted leading pill | center title,
/// or a bare undo glyph when the scene has no title (the canvas) | an ink
/// trailing pill. Both pills draw at the design's 34 pt and hit-test at 44.
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
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                    .buttonStyle(NavPill(prominent: false))
                }

                Spacer()

                if let trailing {
                    Button(trailing, action: onTrailing)
                        .buttonStyle(NavPill(prominent: true))
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }
}

/// The handoff's 34 pt navigation pill: frosted white for the way back, ink
/// for the way forward.
struct NavPill: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sans.font(size: 13, weight: 600))
            .foregroundStyle(prominent ? Palette.onInk : Palette.ink)
            .padding(.horizontal, 16)
            .frame(minWidth: 60, minHeight: 34)
            .background(
                Capsule()
                    .fill(prominent ? Palette.ink : Color.white.opacity(0.72))
                    .overlay(
                        Capsule().strokeBorder(Palette.ink.opacity(prominent ? 0 : 0.07), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .minimumHitTarget()
    }
}
