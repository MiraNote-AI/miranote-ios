import MiraNoteKit
import SwiftUI

/// The photo trigger's landing: a silent, full-screen story of one
/// outing's photos that plays by itself -- the peak first for 3 s with the
/// day and place, the rest by time for 2 s each, nothing between them --
/// then gathers them onto one card with the fact line, the detail line, a
/// question and the button that opens them as a canvas draft.
///
/// Tap the right two thirds for the next photo, the left third for the
/// previous; swipe either way; hold to pause.
struct PhotoTriggerView: View {
    let memory: TriggerMemory
    /// The bucket's name for the menu note (Chinese).
    var bucketName: String?
    /// False for the `other` bucket: only "Not this day" is offered.
    var allowsFewer = true
    /// "P1" -> localIdentifier.
    let photoIds: [String: String]
    let library: TriggerPhotoProviding
    var onClose: () -> Void
    /// The button: open the memory as a canvas draft.
    var onKeep: (TriggerMemory) -> Void
    /// The menu's choice, for the scheduler.
    var onMenu: (MenuAction) -> Void = { _ in }
    /// The story reached its ending.
    var onFinished: () -> Void = {}

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
    /// The "..." menu's answer, at the foot of the screen for a moment.
    @State private var note: MenuNote?
    /// The button was pressed and the draft is being made.
    @State private var keeping = false
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
            guard phase == .story, note == nil else { return }
            if menuShown { clock.pause() } else { clock.resume() }
        }
        .confirmationDialog("", isPresented: $menuShown, titleVisibility: .hidden) {
            if allowsFewer { Button("Fewer like this") { show(.fewerLikeThis) } }
            Button("Not this day") { show(.notThisDay) }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: note) { await holdNote() }
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
                .accessibilityIdentifier("trigger.photo.\(current?.photo.id ?? "")")
                .accessibilityValue(
                    current.map(Self.showsWhole) == true ? Text("Shown whole") : Text("Fills the screen")
                )
                .accessibilityAdjustableAction { direction in
                    direction == .increment ? advance() : goBack()
                }
                .accessibilityHidden(phase != .story)

            firstFrameLabel(stage)

            TriggerEndingText(ending: memory.ending, shown: phase == .settled,
                              top: stage.card(settled: true).maxY, insets: stage.insets, keeping: keeping) {
                guard !keeping else { return }
                keeping = true
                onKeep(memory)
            }
            .frame(width: stage.size.width, height: stage.size.height)

            if phase == .loading {
                ProgressView()
                    .tint(Palette.taupe)
                    .frame(width: stage.size.width, height: stage.size.height)
            }

            // Over the loading indicator: Close works from the first moment.
            chrome(stage)

            if let note {
                MenuNoteView(note: note, bucket: bucketName ?? memory.bucket, bottom: stage.insets.bottom)
                    .frame(width: stage.size.width, height: stage.size.height, alignment: .bottom)
            }
        }
    }

    private static func showsWhole(_ photo: StoryPhoto) -> Bool {
        FacePreservingCrop.showsWhole(imageSize: photo.image.size)
    }

    private func photoLayer(_ stage: TriggerStage) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                let look = stage.look(for: offset, current: index, phase: phase)
                FaceAwarePhoto(photo: photo, whole: look.corner == 0 && Self.showsWhole(photo))
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
            .accessibilityIdentifier("trigger.firstFrameLabel")
            .accessibilityHidden(!(phase == .story && index == 0))
    }

    /// Progress segments over the story, then close and more -- white on the
    /// photos, ink on the paper while loading and once the card has landed.
    /// Only Close shows while the photos load.
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
                chromeButton("xmark", label: "Close", id: "trigger.close", action: onClose)
                Spacer()
                if phase != .loading {
                    chromeButton("ellipsis", label: "More", id: "trigger.more") { menuShown = true }
                }
            }
            .padding(.horizontal, 6)
            .foregroundStyle(onPaper ? Palette.ink : Color.white)
            .shadow(color: .black.opacity(onPaper ? 0 : 0.25), radius: 4, y: 1)
            .animation(.easeInOut(duration: 0.3), value: phase.isEnding)
        }
        .padding(.top, stage.insets.top + 8)
        .frame(width: stage.size.width)
    }

    /// No photo behind the chrome: the paper while loading, the ending.
    private var onPaper: Bool { phase == .loading || phase.isEnding }

    private func chromeButton(_ symbol: String, label: LocalizedStringKey, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

}

/// Playback, the menu and the gestures.
extension PhotoTriggerView {
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
        return clock.elapsed(at: date) / Self.dwell(current.photo)
    }

    /// Plays once three photos are decoded (`StoryStart`); the rest join
    /// while they are on screen. Fewer than three in all: Home, quietly.
    private func start() async {
        guard phase == .loading else { return }
        for await photo in StoryPhoto.stream(memory, photoIds: photoIds, from: library) {
            photos.append(photo)
            if phase == .loading {
                if StoryStart.decide(ready: photos.count, allTried: false) == .play { play() }
            } else if waitingForNext {
                waitingForNext = false
                advance()
            }
        }
        // Closed while loading: nothing more to do here (the cover may be
        // another by now).
        guard !Task.isCancelled else { return }
        loadingDone = true
        if phase == .loading {
            if StoryStart.decide(ready: photos.count, allTried: true) == .play { play() } else { onClose() }
        } else if waitingForNext {
            waitingForNext = false
            advance()
        }
    }

    private func play() {
        phase = .story
        clock = .started()
    }

    /// Waits out what is left of the current photo's time, then moves on.
    /// Restarted by every change of the clock: a new photo, a pause, a resume.
    private func playCurrent() async {
        guard phase == .story, clock.isRunning, let current else { return }
        let remaining = Self.dwell(current.photo) - clock.elapsed(at: .now)
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
        onFinished()
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

    // MARK: The menu

    private func show(_ choice: MenuNote) {
        onMenu(choice.action)
        if phase == .story { clock.pause() }
        withAnimation(.easeOut(duration: 0.2)) { note = choice }
    }

    /// "Fewer like this" shows for 2 s, then the story carries on; "not
    /// this day" shows, then the story closes.
    private func holdNote() async {
        guard let shown = note else { return }
        try? await Task.sleep(for: .seconds(MenuNote.duration))
        guard !Task.isCancelled else { return }
        switch shown {
        case .fewerLikeThis:
            withAnimation(.easeIn(duration: 0.2)) { note = nil }
            if phase == .story { clock.resume() }
        case .notThisDay:
            onClose()
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
                    if dx < 0 { advance() } else { goBack() }
                } else if held < Self.tapLimit, abs(dx) < 10, abs(dy) < 10 {
                    if value.location.x < width / 3 { goBack() } else { advance() }
                } else {
                    clock.resume()
                }
            }
    }
}
