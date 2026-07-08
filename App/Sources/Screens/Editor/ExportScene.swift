import SwiftUI

/// Flow 7 Scene 10: export -- format and quality choices with a full-width
/// Save to Photos action. No instrument panel; this is the terminal step.
struct ExportScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            leading: "Back",
            leadingSymbol: "chevron.left",
            title: "Export",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Final page preview"
            ) {
                PlacedSticker()
            }
        } bottom: {
            ContextCard(
                title: "Export & save",
                subtitle: "Choose format and quality before saving."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Chip(text: "PNG", selected: true)
                        Chip(text: "PDF")
                        Chip(text: "JPG")
                        Chip(text: "Print")
                        Spacer()
                    }
                    Text("Quality")
                        .font(.miraLabel)
                        .foregroundStyle(Palette.textSecondary)
                    HStack(spacing: 8) {
                        Chip(text: "Standard")
                        Chip(text: "High")
                        Chip(text: "Original")
                        Spacer()
                    }
                    saveButton
                        .padding(.top, 2)
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: actions.save) {
            Text("Save to Photos")
                .font(.miraPill)
                .foregroundStyle(Palette.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(Palette.ink))
        }
        .buttonStyle(.plain)
    }
}
