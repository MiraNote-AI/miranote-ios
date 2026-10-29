import MiraNoteKit
import SwiftUI

/// The photo trigger's landing (v0): a silent, full-screen story of one
/// outing's photos that plays by itself -- 2 s each, 3 s on the peak photo,
/// nothing between them -- then gathers them onto one card with the day's
/// place, a question and a way to keep it.
///
/// Tap the right two thirds for the next photo, the left third for the
/// previous; swipe either way; hold to pause.
struct PhotoTriggerView: View {
    let memory: TriggerMemory
    let source: TriggerMemorySource
    var onClose: () -> Void

    @State private var photos: [StoryPhoto] = []
    /// Photos arrive one by one; until the last has, the story may run
    /// ahead of them and wait.
    @State private var loadingDone = false
    @State private var waitingForNext = false
    @State private var phase: TriggerStage.Phase = .loading
    @State private var index = 0
    @State private var clock = StoryClock()
    /// When the finger now on the story went down; nil when none is.
    @State private var touchStart: Date?
    @State private var menuShown = false
    @State private var canvasNoticeShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A held finger that has not moved is a pause, not a tap, after this.
    private static let tapLimit: TimeInterval = 0.25
    private static let swipeDistance: CGFloat = 50

    var body: some View {
        // The outer reader keeps the safe area so it can report the insets;
        // the inner one lays everything out across the whole screen.
        GeometryReader { safe in
            GeometryReader { proxy in
                stageView(TriggerStage(size: proxy.size, insets: safe.safeAreaInsets,
                                       count: photos.count, reduceMotion: reduceMotion))
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: index)
        .task { await start() }
        .task(id: clock) { await playCurrent() }
        .onChange(of: menuShown) {
            guard phase == .story else { return }
            if menuShown { clock.pause() } else { clock.resume() }
        }
        .confirmationDialog("", isPresented: $menuShown, titleVisibility: .hidden) {
            // v0: both only close the menu.
            Button(TriggerCopy.fewerLikeThis) {}
            Button(TriggerCopy.notThisDay) {}
            Button(TriggerCopy.cancel, role: .cancel) {}
        }
        .alert(TriggerCopy.canvasSoon, isPresented: $canvasNoticeShown) {
            Button(TriggerCopy.ok, action: onClose)
        }
    }

    // MARK: Layers

    private func stageView(_ stage: TriggerStage) -> some View {
        ZStack(alignment: .topLeading) {
            Palette.paper

            card(stage)

            photoLayer(stage)
                .contentShape(Rectangle())
                .gesture(storyGesture(width: stage.size.width))
                .allowsHitTesting(phase == .story)
                .accessibilityElement()
                .accessibilityLabel("Photo \(index + 1) of \(storyLength)")
                .accessibilityAdjustableAction { direction in
                    direction == .increment ? advance() : goBack()
                }
                .accessibilityHidden(phase != .story)

            firstFrameLabel(stage)

            TriggerEndingText(ending: memory.ending, shown: phase == .settled,
                              top: stage.card(settled: true).maxY, insets: stage.insets) {
                canvasNoticeShown = true
            }
            .frame(width: stage.size.width, height: stage.size.height)

            chrome(stage)

            if phase == .loading || phase == .failed {
                loadingOrFailure
                    .frame(width: stage.size.width, height: stage.size.height)
            }
        }
    }

    private func photoLayer(_ stage: TriggerStage) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                let look = stage.look(for: offset, current: index, phase: phase)
                FaceAwarePhoto(photo: photo)
                    .frame(width: look.rect.width, height: look.rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: look.corner, style: .continuous))
                    .rotationEffect(.degrees(look.rotation))
                    .position(x: look.rect.midX, y: look.rect.midY)
                    .opacity(look.opacity)
                    // The incoming photo fades in over the outgoing one.
                    .zIndex(offset == index ? 1 : 0)
                    .animation(gatherAnimation(for: offset), value: phase)
            }
        }
        .frame(width: stage.size.width, height: stage.size.height)
    }

    /// The white card the photos land on, with its warm hairline.
    private func card(_ stage: TriggerStage) -> some View {
        let rect = stage.card(settled: phase == .settled)
        return RoundedRectangle(cornerRadius: TriggerStage.cardCorner, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: TriggerStage.cardCorner, style: .continuous)
                    .strokeBorder(Color(hex: 0xE4DFD3), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x544738).opacity(0.08), radius: 18, y: 12)
            .frame(width: rect.width, height: rect.height)
            .scaleEffect(phase.isEnding ? 1 : 1.04)
            .position(x: rect.midX, y: rect.midY)
            .opacity(phase.isEnding ? 1 : 0)
            .animation(phase == .gathered ? .easeOut(duration: 0.5) : gatherAnimation(for: 0), value: phase)
    }

    /// Only the first photo carries words: the day and the place, quietly.
    private func firstFrameLabel(_ stage: TriggerStage) -> some View {
        Text(memory.story.firstFrameLabel)
            .font(Sans.font(size: 15, weight: 500))
            .foregroundStyle(Color.white.opacity(0.88))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            .lineLimit(1)
            .padding(.leading, 20)
            .padding(.bottom, stage.insets.bottom + 26)
            .frame(width: stage.size.width, height: stage.size.height, alignment: .bottomLeading)
            .opacity(phase == .story && index == 0 ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Progress segments over the story, then close and more -- white on the
    /// photos, ink on the paper once the card has landed.
    private func chrome(_ stage: TriggerStage) -> some View {
        VStack(spacing: 4) {
            StoryProgressBar(count: storyLength, index: index, fraction: 0)
                .hidden()
                .overlay {
                    TimelineView(.animation(paused: !clock.isRunning)) { context in
                        StoryProgressBar(count: storyLength, index: index, fraction: progress(at: context.date))
                    }
                }
                .opacity(phase == .story ? 1 : 0)
                .padding(.horizontal, 12)

            HStack {
                chromeButton("xmark", label: TriggerCopy.close, action: onClose)
                Spacer()
                chromeButton("ellipsis", label: TriggerCopy.more) { menuShown = true }
            }
            .padding(.horizontal, 6)
            .foregroundStyle(phase.isEnding ? Palette.ink : Color.white)
            .shadow(color: .black.opacity(phase.isEnding ? 0 : 0.25), radius: 4, y: 1)
            .animation(.easeInOut(duration: 0.3), value: phase.isEnding)
        }
        .padding(.top, stage.insets.top + 8)
        .frame(width: stage.size.width)
        .opacity(phase == .loading ? 0 : 1)
    }

    private func chromeButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var loadingOrFailure: some View {
        if phase == .failed {
            VStack(spacing: 16) {
                Text(TriggerCopy.photosFailed)
                    .font(.miraBody)
                    .foregroundStyle(Palette.textSecondary)
                Button(TriggerCopy.close, action: onClose)
                    .buttonStyle(SoftPill())
            }
        } else {
            ProgressView()
                .tint(Palette.taupe)
        }
    }

    // MARK: Playback

    /// Segments in the progress bar: every photo the memory lists, until
    /// loading shows how many could actually be read.
    private var storyLength: Int {
        loadingDone ? photos.count : memory.storyPhotos.count
    }

    private var current: StoryPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    private func progress(at date: Date) -> Double {
        guard let current else { return 0 }
        return clock.elapsed(at: date) / TriggerMemory.dwell(for: current.photo)
    }

    /// Plays from the first photo as soon as it is decoded; the rest join
    /// while it is on screen.
    private func start() async {
        guard phase == .loading else { return }
        for await photo in StoryPhoto.stream(memory, from: source) {
            photos.append(photo)
            if phase == .loading {
                phase = .story
                clock = .started()
            } else if waitingForNext {
                waitingForNext = false
                advance()
            }
        }
        loadingDone = true
        if photos.isEmpty {
            phase = .failed
        } else if waitingForNext {
            waitingForNext = false
            advance()
        }
    }

    /// Waits out what is left of the current photo's time, then moves on.
    /// Restarted by every change of the clock: a new photo, a pause, a resume.
    private func playCurrent() async {
        guard phase == .story, clock.isRunning, let current else { return }
        let remaining = TriggerMemory.dwell(for: current.photo) - clock.elapsed(at: .now)
        try? await Task.sleep(for: .seconds(max(0, remaining)))
        guard !Task.isCancelled else { return }
        advance()
    }

    private func advance() {
        guard phase == .story else { return }
        if index < photos.count - 1 {
            show(index + 1)
        } else if !loadingDone {
            waitingForNext = true
        } else {
            gather()
        }
    }

    private func goBack() {
        guard phase == .story else { return }
        if index > 0 {
            show(index - 1)
        } else {
            clock = .started()
        }
    }

    private func show(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            index = next
        }
        clock = .started()
    }

    /// The story's last photo is done: gather everything onto the card, and
    /// once it has landed, lift it and bring in the words.
    private func gather() {
        clock.pause()
        // Without animation: the other photos jump to their starts while
        // still invisible, so the next change can fly them in from there.
        phase = .scatter
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            phase = .gathered
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.7 : 1.25))
            phase = .settled
        }
    }

    /// Per-photo motion for phase changes; nil (instant) for the scatter.
    /// The small photos follow the peak a beat apart.
    private func gatherAnimation(for offset: Int) -> Animation? {
        switch phase {
        case .gathered:
            if reduceMotion { return .easeInOut(duration: 0.5) }
            let delay = offset == photos.count - 1 ? 0 : 0.05 + 0.035 * Double(offset)
            return .spring(duration: 0.95, bounce: 0.22).delay(delay)
        case .settled:
            return .easeInOut(duration: 0.5)
        default:
            return nil
        }
    }

    // MARK: Gestures

    /// One gesture for the whole story: the finger going down pauses; a
    /// quick still lift is a tap (left third back, the rest forward); a
    /// sideways drag is a swipe; anything else was a hold, and play resumes.
    private func storyGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard touchStart == nil else { return }
                touchStart = .now
                clock.pause()
            }
            .onEnded { value in
                let held = Date.now.timeIntervalSince(touchStart ?? .now)
                touchStart = nil
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > Self.swipeDistance, abs(dx) > abs(dy) {
                    dx < 0 ? advance() : goBack()
                } else if held < Self.tapLimit, abs(dx) < 10, abs(dy) < 10 {
                    value.location.x < width / 3 ? goBack() : advance()
                } else {
                    clock.resume()
                }
            }
    }
}
