import MiraNoteKit
import Observation
import SwiftUI
import UIKit

/// The Image tool's AI Image source (screen 23's third pill): words in, a
/// couple of paintings to pick from. A painting on its way, or waiting to
/// be picked, took seconds and real credits -- only Cancel lets it go, and
/// a result Cancel let go of never shows up afterwards.
@MainActor
@Observable
final class AIImageDraft {
    var prompt = ""
    private(set) var candidates: [Data] = [] {
        // Decoded once as they arrive: the sheet redraws with every
        // keystroke in the prompt.
        didSet { previews = candidates.map { UIImage(data: $0) } }
    }
    private(set) var previews: [UIImage?] = []
    private(set) var generating = false
    var notice: String?
    /// The words the showing candidates were painted from.
    private var paintedPrompt = ""
    /// Bumped by every generate and Cancel; a slower call checks it.
    private var generation = 0
    private var task: Task<Void, Never>?

    /// A painting is on its way or waits to be picked.
    var holdsWork: Bool { generating || !candidates.isEmpty }

    var canGenerate: Bool { !generating && !words.isEmpty }

    private var words: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The api's art command, as the dev Image panel's generate ran it.
    func generate(with studio: ImageStudioService) {
        let words = self.words
        guard !words.isEmpty, !generating else { return }
        generation += 1
        let token = generation
        generating = true
        notice = nil
        candidates = []
        task = Task {
            do {
                let images = try await studio.generate(kind: .art, prompt: words)
                guard token == generation else { return }
                // Two to pick from, as Mira's own image choices offer.
                candidates = Array(images.prefix(2))
                paintedPrompt = words
                if candidates.isEmpty { notice = String(appCopy: "Mira couldn't paint that one -- try other words?") }
            } catch {
                guard token == generation else { return }
                notice = (error as? LocalizedError)?.errorDescription
                    ?? String(appCopy: "Generating didn't work this time. Try again?")
            }
            generating = false
        }
    }

    /// Cancel: the running painting and the waiting candidates go for good.
    func discard() {
        generation += 1
        task?.cancel()
        task = nil
        generating = false
        candidates = []
        notice = nil
    }

    /// Hands candidate `index` and the words that name it to `place`; once
    /// it lands the draft is done. `place` false (its bytes could not be
    /// stored): the candidates stay for another try.
    @discardableResult
    func pick(_ index: Int, place: (Data, String) -> Bool) -> Bool {
        guard !generating, candidates.indices.contains(index) else { return false }
        guard place(candidates[index], paintedPrompt) else {
            notice = String(appCopy: "That picture couldn't be saved. Try again?")
            return false
        }
        candidates = []
        prompt = ""
        notice = nil
        return true
    }
}

/// The AI Image sheet over the canvas, in screen 23's glass: the words go
/// in the composer below; the sticker panel's dot ring while Mira paints,
/// then the candidates -- a tap puts one on the page.
struct AIImageSheet: View {
    let draft: AIImageDraft
    var onPick: (Int) -> Void

    var body: some View {
        GlassSheet(
            title: "AI Image",
            subtitle: "Describe an image below -- Mira paints a couple to pick from.",
            titleSize: 22
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if draft.generating {
                    DotRingSpinner(diameter: 80)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .accessibilityIdentifier("image.generating")
                } else if !draft.candidates.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(draft.previews.enumerated()), id: \.offset) { index, preview in
                            Button {
                                onPick(index)
                            } label: {
                                candidate(preview)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Image \(index + 1)")
                            .accessibilityIdentifier("image.result.\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if let notice = draft.notice {
                    Text(notice)
                        .font(.miraLabel)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("image.notice")
                }
            }
        }
    }

    /// 120 pt r18, like the Recents cells and the photo tiles.
    private func candidate(_ preview: UIImage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.imageCorner)
        return Group {
            if let image = preview {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GradientPlaceholder()
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(shape)
        .contentShape(shape)
    }
}
