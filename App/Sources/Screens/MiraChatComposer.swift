import MiraNoteKit
import PhotosUI
import SwiftUI

/// Handoff screen 02's composer surface (342x54, r27, paper at 92% with a
/// white rim) laid out the way WeChat's is, per the owner: voice toggle far
/// left, the field (or "Hold to talk"), and "+" on the right that becomes
/// the design's Send pill once there is something to send. No emoji button.
///
/// Voice is voice-to-text: releasing the hold transcribes into the field
/// for editing; nothing is sent until the user taps Send. "+" opens a glass
/// tray with Photos and Camera; picked photos stage as thumbnails inside
/// the composer.
struct MiraChatComposer: View {
    @Bindable var viewModel: ChatViewModel

    private enum Mode { case text, voice }

    @State private var mode: Mode = .text
    @State private var trayOpen = false
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    /// A finger is down on "Hold to talk".
    @State private var holding = false
    /// The hold as the gesture system sees it: it lets go even when the
    /// system takes the touch (the first-use mic alert, a call) and the
    /// gesture's onEnded never comes.
    @GestureState private var touching = false
    /// Bumped to take a hold's touch away (-UITEST, `interruptHoldIfAsked`).
    @State private var holdEpoch = 0
    /// The finger slid far enough up that letting go cancels.
    @State private var releaseCancels = false
    /// Staged photos' thumbnails, decoded once per photo.
    @State private var thumbnails: [StagedPhoto.ID: UIImage] = [:]
    @State private var fieldFocused = false
    @Environment(\.scenePhase) private var scenePhase

    /// Upward travel past which a release cancels the clip.
    private static let cancelTravel: CGFloat = 60

    var body: some View {
        VStack(spacing: 12) {
            if let caption = statusCaption {
                Text(caption)
                    .font(Sans.font(size: 13, weight: 500))
                    .foregroundStyle(ChatMetrics.muted)
                    .transition(.opacity)
                    .accessibilityIdentifier("chat.voice.caption")
            } else if let hint = viewModel.hint {
                hintRow(hint)
            }
            if trayOpen {
                tray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            surface
        }
        .padding(.horizontal, Metrics.chromeInset)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.2), value: trayOpen)
        .animation(.easeOut(duration: 0.15), value: showsSend)
        .animation(.easeOut(duration: 0.15), value: viewModel.staged.count)
        .onChange(of: fieldFocused) { _, focused in
            if focused { trayOpen = false }
        }
        .onChange(of: viewModel.draft) { viewModel.hint = nil }
        // A hold the system cancelled never reaches onEnded: the mic stops
        // with it. Leaving the chat or the app stops it too.
        .onChange(of: touching) { _, down in
            guard !down else { return }
            Task { @MainActor in
                // onEnded, when it comes, has run by now.
                guard holding else { return }
                holding = false
                releaseCancels = false
                viewModel.cancelVoice()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopListening() }
        }
        .onDisappear { stopListening() }
        .photosPicker(
            isPresented: $showPicker,
            selection: $pickerItems,
            maxSelectionCount: max(1, ChatViewModel.maxStagedImages - viewModel.staged.count - viewModel.loadingImages),
            matching: .images
        )
        .onChange(of: pickerItems) { _, items in stagePicked(items) }
        .fullScreenCover(isPresented: $showCamera) { camera }
    }

    @ViewBuilder private var camera: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            UITestCameraStub {
                viewModel.stageImage(MockImageStudioService.tinyPNG)
                showCamera = false
            }
        } else {
            systemCamera
        }
        #else
        systemCamera
        #endif
    }

    private var systemCamera: some View {
        CameraCapture { image in
            if let data = image.downscaled() { viewModel.stageImage(data) }
        }
        .ignoresSafeArea()
    }

    // MARK: - Surface

    private var surface: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.staged.isEmpty || viewModel.loadingImages > 0 {
                stagedStrip
            }
            HStack(alignment: .bottom, spacing: 8) {
                voiceToggle
                switch mode {
                case .text: field
                case .voice: holdBar
                }
                rightSlot
            }
        }
        .padding(10)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 27)
                .fill(Color(hex: 0xF8F5EC).opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 27).strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
        )
        .overlay {
            if case .recording(let since) = viewModel.voice {
                recorderBar(since: since)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isRecording)
    }

    /// The design's mode-tile look: tool surface, hairline rim, ink glyph.
    private func circleButton(symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Palette.toolSurface)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                )
                .padding(5)
                .contentShape(Circle())
                .padding(-5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copy: label))
        .accessibilityIdentifier(id)
    }

    private var voiceToggle: some View {
        circleButton(
            symbol: mode == .text ? "mic" : "keyboard",
            label: mode == .text ? "Voice input" : "Keyboard",
            id: "chat.voice.toggle"
        ) {
            trayOpen = false
            if mode == .text {
                mode = .voice
                fieldFocused = false
            } else {
                // Back to the keyboard (also from VoiceOver, whose tap
                // toggle leaves a take running): the take stops.
                stopListening()
                mode = .text
                fieldFocused = true
            }
        }
    }

    private var field: some View {
        // WeChat's field: one line growing to four. The keyboard's Send key
        // sends through sendDraft (so its guards apply) and the keyboard
        // stays up for the next message; a paste never sends.
        ChatTextView(text: $viewModel.draft, isFocused: $fieldFocused, font: Sans.uiFont(size: 17, weight: 400)) {
            Task { await viewModel.sendDraft() }
        }
        .frame(maxWidth: .infinity, minHeight: ChatTextView.minHeight, alignment: .leading)
        .overlay(alignment: .leading) {
            if viewModel.draft.isEmpty {
                Text("Ask Mira anything...")
                    .font(Sans.font(size: 17, weight: 400))
                    .foregroundStyle(ChatMetrics.muted)
                    .allowsHitTesting(false)
            }
        }
    }

    /// WeChat's press-and-hold bar in the left nav pill's look. Release
    /// transcribes into the field; sliding up past 60 pt cancels. VoiceOver
    /// users get a tap toggle instead of a hold.
    private var holdBar: some View {
        Text(viewModel.voice == .transcribing ? "Transcribing..." as LocalizedStringKey : "Hold to talk")
            .font(Sans.font(size: 14, weight: 600))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.07), lineWidth: 1))
            )
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        if !holding {
                            holding = true
                            guard viewModel.voice == .idle else { return }
                            viewModel.startVoice()
                            #if DEBUG
                            interruptHoldIfAsked()
                            #endif
                        }
                        releaseCancels = value.translation.height < -Self.cancelTravel
                    }
                    .onEnded { _ in
                        holding = false
                        let cancels = releaseCancels
                        releaseCancels = false
                        if cancels {
                            viewModel.cancelVoice()
                        } else {
                            finishVoice()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(isRecording ? Text("Stop and transcribe") : Text("Hold to talk"))
            .accessibilityHint("Your words go into the message field to edit before sending.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isRecording { finishVoice() } else { viewModel.startVoice() }
            }
            .accessibilityIdentifier("chat.voice.hold")
            .id(holdEpoch)
    }

    #if DEBUG
    /// -UITEST only: `-HOLD_INTERRUPT_AFTER <ms>` takes the hold's touch away
    /// mid-hold, as the system does (the first-use mic alert, a call): the
    /// bar is rebuilt, its gesture torn down, and onEnded never comes.
    private func interruptHoldIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        let delay = UserDefaults.standard.integer(forKey: "HOLD_INTERRUPT_AFTER")
        guard delay > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            holdEpoch += 1
        }
    }
    #endif

    /// "+" stays, so photos can be added after typing (owner decision);
    /// Send joins it once there is something to send.
    private var rightSlot: some View {
        HStack(spacing: 8) {
            circleButton(symbol: "plus", label: "Add photos", id: "chat.plus") {
                fieldFocused = false
                trayOpen.toggle()
            }
            if showsSend {
                Button {
                    Task { await viewModel.sendDraft() }
                } label: {
                    Text("Send")
                        .font(Sans.font(size: 14, weight: 700))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 54, height: 34)
                        .background(Capsule().fill(Palette.ink))
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .opacity(viewModel.canSend ? 1 : 0.45)
                .accessibilityIdentifier("chat.send")
                .transition(.opacity)
            }
        }
    }

    // MARK: - Voice

    private var isRecording: Bool {
        if case .recording = viewModel.voice { return true }
        return false
    }

    private var showsSend: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.staged.isEmpty || viewModel.loadingImages > 0
    }

    /// The chat closed or the app left the foreground mid-take: the mic
    /// stops and nothing is kept.
    private func stopListening() {
        holding = false
        releaseCancels = false
        viewModel.cancelVoice()
    }

    private var statusCaption: String? {
        guard isRecording else { return nil }
        return releaseCancels
            ? String(appCopy: "Release to cancel")
            : String(appCopy: "Release to finish, slide up to cancel")
    }

    /// The words land in the field with the keyboard up, ready to fix.
    private func finishVoice() {
        Task {
            let before = viewModel.draft
            await viewModel.finishVoice()
            if viewModel.draft != before {
                mode = .text
                fieldFocused = true
            }
        }
    }

    /// Handoff screen 08's live bar, inside the composer: ink (clay once a
    /// release would cancel), moving bars and the clock.
    private func recorderBar(since start: Date) -> some View {
        HStack(spacing: 14) {
            TimelineView(.periodic(from: start, by: 1)) { context in
                // The system face: Josefin has no tabular digits.
                Text(CanvasScene.timestamp(context.date.timeIntervalSince(start)))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.warmWhite)
            }
            LiveBars()
                .frame(maxWidth: .infinity)
            Image(systemName: releaseCancels ? "xmark" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.warmWhite)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 27)
                .fill(releaseCancels ? Color(hex: 0x8C4A3A) : Palette.ink)
        )
        // A live mic is never invisible to VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue(statusCaption ?? "")
        .accessibilityIdentifier("chat.voice.recording")
    }

    private func hintRow(_ hint: ChatHint) -> some View {
        HStack(spacing: 8) {
            Text(hint.text)
                .font(Sans.font(size: 13, weight: 500))
                .foregroundStyle(ChatMetrics.muted)
                .multilineTextAlignment(.center)
            if hint.opensSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Settings", destination: url)
                    .font(Sans.font(size: 13, weight: 700))
                    .foregroundStyle(Palette.ink)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.hint")
    }

    // MARK: - Photos

    /// The WeChat attachment panel in the handoff's glass-sheet language
    /// with screen 27's photo-edit tiles.
    private var tray: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to your message")
                .font(Sans.font(size: 20, weight: 700))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                trayTile("Photos", symbol: "photo.on.rectangle", id: "chat.tray.photos") {
                    trayOpen = false
                    showPicker = true
                }
                trayTile("Camera", symbol: "camera", id: "chat.tray.camera") {
                    trayOpen = false
                    openCamera()
                }
            }
        }
        .padding(.horizontal, 21)
        .padding(.top, 17)
        .padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30).fill(Palette.paper.opacity(0.56)))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.46), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.1), radius: 13, y: 12)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.tray")
    }

    private func trayTile(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                Text(copy: label)
                    .font(Sans.font(size: 13, weight: 700))
            }
            .foregroundStyle(ChatMetrics.muted)
            .frame(width: 62, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Palette.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.04), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canStageMoreImages)
        .opacity(viewModel.canStageMoreImages ? 1 : 0.45)
        .accessibilityIdentifier(id)
    }

    private var stagedStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(viewModel.staged.enumerated()), id: \.element.id) { index, photo in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = thumbnails[photo.id] {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Palette.cardFill
                        }
                    }
                    .frame(width: 56, height: 56)
                    .task(id: photo.id) {
                        if thumbnails[photo.id] == nil { thumbnails[photo.id] = UIImage(data: photo.data) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement()
                    .accessibilityLabel("Photo \(index + 1) to send")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("chat.staged.\(index)")

                    let label = String(appCopy: "Remove photo \(index + 1)")
                    removeBadge(label: label, id: "chat.staged.\(index).remove") {
                        viewModel.removeStagedImage(at: index)
                    }
                }
            }
            // Picks still loading hold their place (and Send) -- until they
            // load, time out, or are removed here.
            ForEach(viewModel.loadingPicks, id: \.self) { pick in
                ZStack(alignment: .topTrailing) {
                    ProgressView()
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardFill))
                        .accessibilityLabel("Photo loading")
                        .accessibilityIdentifier("chat.staged.loading")
                    removeBadge(label: String(appCopy: "Remove the loading photo"), id: "chat.staged.loading.remove") {
                        viewModel.removeLoadingPick(pick)
                    }
                }
            }
        }
        .padding(.top, 4)
        .onChange(of: viewModel.staged) { _, staged in
            let ids = Set(staged.map(\.id))
            thumbnails = thumbnails.filter { ids.contains($0.key) }
        }
    }

    /// The ink x on a staged photo's corner.
    private func removeBadge(label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.onInk)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Palette.ink))
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 14, y: -14)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Picks load side by side, counted toward the four; Send waits for
    /// them, and one that cannot load (or takes too long) says so.
    private func stagePicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickerItems = []
        let loaders: [@Sendable () async -> Data?] = items.map { item in
            {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                return UIImage(data: data)?.downscaled()
            }
        }
        Task { await viewModel.stagePhotos(loaders) }
    }

    private func openCamera() {
        #if DEBUG
        // UI tests cannot drive the system camera: they stage a canned
        // photo here to exercise the send path, or with -CAMERA_COVER go
        // through the cover with a stand-in camera.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") {
            if arguments.contains("-CAMERA_COVER") {
                showCamera = true
            } else {
                viewModel.stageImage(MockImageStudioService.tinyPNG)
            }
            return
        }
        #endif
        if CameraCapture.isAvailable {
            showCamera = true
            return
        }
        viewModel.hint = ChatHint(text: String(appCopy: "This device has no camera -- try Photos instead."))
    }
}

/// Recorder bars that breathe while the mic is open (static with Reduce
/// Motion): 4 pt wide, r2, 10 pt pitch, 16-42 pt tall.
private struct LiveBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let count = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.onInk.opacity(0.85))
                        .frame(width: 4, height: height(index, time: time))
                }
            }
            .frame(height: 42)
        }
    }

    private func height(_ index: Int, time: TimeInterval) -> CGFloat {
        let wave = sin(time * 5 + Double(index) * 0.9) * 0.5 + 0.5
        let shape = sin(Double(index) * 1.7) * 0.25 + 0.75
        return 16 + CGFloat(wave * shape) * 26
    }
}
