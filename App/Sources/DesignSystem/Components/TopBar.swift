import SwiftUI

/// Editor top bar (2026-10-07 handoff): a frosted leading pill | center title,
/// or the undo glyph when the scene has no title (the canvas) | an ink
/// trailing pill. Both pills draw at the design's 34 pt (70 and 60 wide) and
/// hit-test at 44. The center stays optically centered regardless of the
/// side widths.
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
    /// The way-back label is muted on editor scenes; text editing's
    /// "Cancel" is drawn in ink (screens 10-20).
    var leadingMuted = true
    var leadingID: String?
    var trailingID: String?
    /// The leading pill over the Mira chat's frosted scrim (screen 06):
    /// white@0.54 with a white rim and an ink label.
    var leadingOnGlass = false
    /// Ink; forest (#293322) while a Mira result waits (screen 07).
    var trailingFill = Palette.ink

    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
            } else if let onUndo {
                Button(action: onUndo) {
                    // The handoff's own thin u-turn glyph, 18 pt.
                    Image("nav.undo")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Palette.ink)
                        // 34 tall like the pills, hit-testing at 44: a 44 pt
                        // frame made the canvas header 10 pt taller than the
                        // panels', and content jumped on every switch.
                        .frame(width: 44, height: 34)
                        .minimumHitTarget()
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
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(leading)
                        }
                    }
                    .buttonStyle(NavPill(
                        prominent: false, muted: leadingMuted && !leadingOnGlass, onGlass: leadingOnGlass,
                        width: NavPill.leadingWidth
                    ))
                    .optionalIdentifier(leadingID)
                }

                Spacer()

                if let trailing {
                    Button(trailing, action: onTrailing)
                        .buttonStyle(NavPill(prominent: true, fill: trailingFill, width: NavPill.trailingWidth))
                        .optionalIdentifier(trailingID)
                }
            }
        }
        .padding(.horizontal, Metrics.chromeInset)
        .padding(.top, 2)
        .padding(.bottom, Metrics.navToCanvas)
    }
}

private extension View {
    @ViewBuilder func optionalIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

/// The handoff's 34 pt navigation pill: frosted white for the way back, ink
/// for the way forward. Josefin SemiBold 12. The way-back label is muted
/// #878476 on editor scenes and ink on the Mira chat.
struct NavPill: ButtonStyle {
    static let leadingWidth: CGFloat = 70
    static let trailingWidth: CGFloat = 60

    var prominent: Bool
    var muted = false
    /// Over the chat's glass scrim: white@0.54 with a white@0.35 rim.
    var onGlass = false
    /// The prominent pill's fill.
    var fill = Palette.ink
    /// The design's fixed pill width; nil sizes the pill to its label.
    var width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.miraNav)
            .lineLimit(1)
            .foregroundStyle(prominent ? Palette.onInk : (muted ? Palette.muted : Palette.ink))
            .padding(.horizontal, width == nil ? 16 : 0)
            .frame(width: width, height: 34)
            .frame(minWidth: width == nil ? 60 : nil)
            .background(
                Capsule()
                    .fill(prominent ? fill : Color.white.opacity(onGlass ? 0.54 : 0.72))
                    .overlay(
                        Capsule().strokeBorder(rim, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .minimumHitTarget()
    }

    private var rim: Color {
        if prominent { return .clear }
        return onGlass ? Color.white.opacity(0.35) : Palette.ink.opacity(0.07)
    }
}
