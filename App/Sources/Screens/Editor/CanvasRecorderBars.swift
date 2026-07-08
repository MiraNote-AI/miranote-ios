import MiraNoteKit
import SwiftUI

// The Sound tool's bottom-cluster bars: armed (nothing captured until the
// user presses Record), live recording, and the keep/re-record review.

extension CanvasScene {
    /// Armed: the tool is open but the mic is NOT live. The explicit
    /// Record press is what starts capturing.
    var armedBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic")
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
            Text("Ready when you are")
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("Cancel") { recorderState = .idle }
                .font(.miraLabel)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityIdentifier("recorder.cancel")
            Button(action: startRecording) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Palette.onInk)
                        .frame(width: 7, height: 7)
                    Text("Record")
                        .font(.miraLabel)
                }
                .foregroundStyle(Palette.onInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.record")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
    }

    func recordingBar(since start: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.onInk)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.ink))
            WaveformView(barCount: 26, tint: Palette.ink, maxHeight: 22)
            Spacer()
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text(CanvasScene.timestamp(context.date.timeIntervalSince(start)))
                    .font(.miraLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            Button(action: stopRecording) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
    }

    /// After stopping: listen result, optionally note it, then Re-record or
    /// Keep (v2.1 replaces Revert/Keep for the user's own recording).
    func reviewBar(duration: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(CanvasScene.timestamp(duration))
                .font(.miraLabel)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()

            TextField("Add a note...", text: $reviewNote)
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("recorder.note")

            Button("Re-record") {
                recorderState = .idle
                startRecording()
            }
            .font(.miraLabel)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityIdentifier("recorder.rerecord")

            Button(action: keepRecording) {
                Text("Keep")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.keep")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
    }
}
