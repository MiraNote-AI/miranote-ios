import SwiftUI

/// Flow 7 Scene 03: voice capture. A "Voice memory" card floats on the page;
/// the bottom carries a live recorder bar instead of the Go row.
struct VoiceScene: View {
    var actions = EditorActions()

    var body: some View {
        EditorScaffold(
            title: "Voice input",
            onLeading: actions.leading,
            onTrailing: actions.save
        ) {
            MemoryPage(
                title: "Lunch by the river",
                caption: "Voice note becomes editable writing"
            ) {
                VStack {
                    voiceMemoryCard
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        } bottom: {
            InputModeBar(active: .voice, onSelect: actions.selectMode)
            recorderBar
        }
    }

    private var voiceMemoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Voice memory")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("0:12")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 12) {
                WaveformView(barCount: 22, tint: Palette.taupe, maxHeight: 20)
                Spacer()
                Button(action: actions.go) {
                    Text("Convert to text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.onInk)
                .shadow(color: Palette.ink.opacity(0.12), radius: 10, y: 4)
        )
    }

    private var recorderBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.onInk)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.ink))
            WaveformView(barCount: 30, tint: Palette.ink, maxHeight: 24)
            Spacer()
            Text("0:12")
                .font(.miraLabel)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
    }
}
