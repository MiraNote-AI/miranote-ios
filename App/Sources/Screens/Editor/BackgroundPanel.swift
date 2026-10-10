import MiraNoteKit
import SwiftUI

/// The Background tool's first cut: the default backdrop, or a mood Mira
/// paints. Paper types, colors and curated font sets (handoff screen 05)
/// arrive with the page-style model in a later phase.
struct BackgroundPanel: View {
    @Bindable var editor: CanvasViewModel
    /// Sends a request through the Mira bar's normal turn (working state,
    /// Stop, Keep/Revert receipt).
    var onAsk: (String) -> Void
    var onClose: () -> Void

    /// Each mood becomes a sentence Mira already routes as a background ask
    /// (pinned by BackgroundMoodRoutingTests).
    static let moods = ["Sunset glow", "Soft paper", "Night sky", "Garden"]

    static func ask(for mood: String) -> String {
        "Make the background \(mood.lowercased())"
    }

    var body: some View {
        ContextCard(
            title: "Background",
            subtitle: "Pick a mood and Mira paints it behind your page."
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        editor.setBackground(fileName: "")
                        onClose()
                    } label: {
                        Chip(
                            text: "Default",
                            selected: editor.memory.backgroundFileName.isEmpty,
                            fillWhenSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("background.default")
                    .accessibilityAddTraits(editor.memory.backgroundFileName.isEmpty ? .isSelected : [])

                    ForEach(Self.moods, id: \.self) { mood in
                        Button {
                            onClose()
                            onAsk(Self.ask(for: mood))
                        } label: {
                            Chip(text: mood, systemImage: "sparkles")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("background.mood.\(mood)")
                    }
                }
            }
        }
    }
}
