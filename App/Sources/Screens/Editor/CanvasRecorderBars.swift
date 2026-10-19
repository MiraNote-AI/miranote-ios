import MiraNoteKit
import SwiftUI

// The Voice tool's bars in the composer slot (handoff screen 08): armed
// (nothing captured until the user presses Record) and live recording, both
// in the recorder bar's ink geometry; and the "Sound is attached." sheet
// once Stop has put the take on the page (screen 09).

extension CanvasScene {
    /// Armed: the tool is open but the mic is NOT live. The explicit
    /// Record press is what starts capturing. Same 54 pt ink bar as the
    /// live recorder, so nothing jumps when recording starts.
    var armedBar: some View {
        RecorderBar {
            Button { recorderState = .idle } label: {
                RecorderCircle {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier("recorder.cancel")
            Text("Ready when you are")
                .font(Sans.font(size: 14, weight: 500))
                .foregroundStyle(Palette.onInk.opacity(0.85))
                .padding(.leading, 11)
            Spacer(minLength: 0)
            Button(action: startRecording) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(hex: 0x8C4A3A))
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(Sans.font(size: 14, weight: 700))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Palette.onInk))
                .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.record")
        }
    }

    /// Handoff screen 08: discard circle at 8, twelve live bars from 61,
    /// the clock right-aligned at 289, the stop circle at 299.
    func recordingBar(since start: Date, recorder: AudioRecording) -> some View {
        RecorderBar {
            Button(action: cancelRecording) {
                RecorderCircle {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard recording")
            .accessibilityIdentifier("recorder.discard")
            LiveWaveform(recorder: recorder)
                .padding(.leading, 19)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: start, by: 1)) { context in
                // Right-aligned, so a narrower digit never shifts the clock
                // away from the stop button.
                // The system face: Josefin has no tabular digits, so its
                // clock jittered every second.
                Text(CanvasScene.timestamp(context.date.timeIntervalSince(start)))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.warmWhite)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.trailing, 10)
            Button(action: stopRecording) {
                RecorderCircle {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.ink)
                        .frame(width: 13, height: 13)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("recorder.stop")
        }
    }

    /// Handoff screen 09: the take is already on the page; Revert takes it
    /// off again (record again from Voice), Keep closes the sheet.
    var soundAttachedSheet: some View {
        ResultSheet(
            title: "Sound is attached.",
            detail: "A small marker keeps the page visual-first.",
            revertID: "recorder.revert",
            keepID: "recorder.keep",
            onRevert: revertAttachedSound,
            onKeep: { attachedSound = nil }
        )
    }
}

/// The recorder bar's surface (screen 08): a 54 pt ink capsule with the
/// glass rim, inner highlight and composer shadow; 34 pt circles 8-9 in
/// from either end.
struct RecorderBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: 54)
        .background(
            Capsule()
                .fill(Palette.ink)
                .overlay(InnerTopHighlight(shape: Capsule()))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.46), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.1), radius: 13, y: 12)
        )
        .padding(.horizontal, Metrics.chromeInset)
    }
}

/// The recorder bar's 34 pt #F6F4E8 circle holding a glyph, hit-testing
/// at 44 x 44 while it lays out at 34 wide.
struct RecorderCircle<Glyph: View>: View {
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        glyph()
            .frame(width: 34, height: 34)
            .background(Circle().fill(Palette.onInk))
            .frame(width: 34, height: 44)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
            .padding(.horizontal, -5)
    }
}

/// Twelve 4 pt bars at a 10 pt pitch, driven by the recorder's level. The
/// newest sample enters on the right; each bar scales the handoff's height
/// pattern (20 ... 42 pt) by its sample, so a steady voice draws the
/// designed shape and silence settles to 4 pt ticks.
struct LiveWaveform: View {
    let recorder: AudioRecording

    static let pattern: [CGFloat] = [20, 30, 42, 24, 16, 34, 22, 38, 20, 28, 32, 18]

    @State private var levels = [Float](repeating: 0, count: LiveWaveform.pattern.count)

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Self.pattern.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.onInk.opacity(0.85))
                    .frame(width: 4, height: max(4, Self.pattern[index] * CGFloat(levels[index])))
            }
        }
        .frame(height: 42)
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
        .task {
            // 10 Hz, for as long as the bar is on screen.
            while !Task.isCancelled {
                levels.removeFirst()
                levels.append(recorder.level)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

/// Where a take will land, pulsing on the page while it records (screen
/// 08): a 30 pt forest@0.4 tap circle with its speaker glyph inside a 42 pt
/// ring that breathes outward.
struct PendingSoundMarker: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // The pulse leaves the drawn ring outward and fades.
            Circle()
                .stroke(Palette.forest.opacity(0.5), lineWidth: 2)
                .frame(width: 42, height: 42)
                .scaleEffect(pulsing ? 1.4 : 1)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .fill(Palette.forest.opacity(0.4))
                .overlay(Circle().strokeBorder(Palette.forest.opacity(0.2), lineWidth: 1))
                .frame(width: 42, height: 42)
            SoundMarkerGlyph(fill: Palette.forest.opacity(0.4))
        }
        .frame(width: 42, height: 42)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Recording here")
        .accessibilityIdentifier("recorder.pendingMarker")
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulsing = true }
        }
    }
}

/// The marker's 30 pt tap circle: the handoff's speaker glyph (18 pt) on
/// `fill`, with its soft drop shadow.
struct SoundMarkerGlyph: View {
    var fill: Color = Palette.forest
    var playing = false

    var body: some View {
        Group {
            if playing {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Image("sound.glyph")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(Palette.onInk)
        .frame(width: 30, height: 30)
        .background(
            Circle()
                .fill(fill)
                .shadow(color: Palette.ink.opacity(0.16), radius: 3.5, y: 6)
        )
    }
}
