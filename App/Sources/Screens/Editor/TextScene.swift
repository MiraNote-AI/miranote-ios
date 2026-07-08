import SwiftUI

/// Flow 7 Scene 04.1: text over the page, with the Font/Color/Effect/Bubble
/// styling row above the instrument panel.
struct TextInputScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Text input",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Text over the journal page"
            )
        } bottom: {
            styleChips
            InputModeBar(active: .text, onSelect: actions.selectMode)
            ActionRow(hint: "Type or polish your memory", onGo: actions.go)
        }
    }

    private var styleChips: some View {
        HStack(spacing: 10) {
            Chip(text: "Font", selected: true)
            Chip(text: "Color")
            Chip(text: "Effect")
            Chip(text: "Bubble")
            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
    }
}

/// Flow 7 Scene 04.2: the text-entry state -- dimmed page, the entered story
/// centered on it, styling row, and the keyboard raised.
struct TextStoryScene: View {
    var actions = EditorActions()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(title: "Text input", onTrailing: actions.save)
                SubToolbar()
                MemoryPage(
                    title: "Lunch by the river",
                    caption: "Text over the journal page"
                )
                Spacer()
            }
            .opacity(0.35)

            VStack(spacing: 0) {
                Spacer()
                Text("Sunny afternoon, tiny\nnoodle shop by the bridge")
                    .font(.miraPageTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .padding(.horizontal, 34)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.go() }
                Spacer()
                styleChips
                    .padding(.bottom, 12)
                KeyboardMock()
            }
        }
        .screenBackground()
    }

    private var styleChips: some View {
        HStack(spacing: 10) {
            Chip(text: "Font", selected: true)
            Chip(text: "Color")
            Chip(text: "Effect")
            Chip(text: "Bubble")
            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
    }
}

/// A stylized dark keyboard standing in for the OS keyboard in the text-story
/// snapshot. The real flow raises the system keyboard.
struct KeyboardMock: View {
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Array(row), id: \.self) { char in
                        key(String(char))
                    }
                }
            }
            HStack(spacing: 6) {
                key("space", wide: true)
                key("return")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Palette.forest)
    }

    private func key(_ label: String, wide: Bool = false) -> some View {
        Text(label)
            .font(.system(size: wide ? 11 : 13))
            .foregroundStyle(Palette.onInk)
            .frame(minWidth: 24, maxWidth: wide ? .infinity : nil, minHeight: 32)
            .padding(.horizontal, wide ? 0 : 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.onInk.opacity(0.14)))
    }
}
