import MiraNoteKit
import SwiftUI

/// Handoff screen 03: the PREFERENCES card -- Appearance and Language rows
/// with their current values, and the text-size slider. The ACCOUNT card
/// (email, Log Out) and PRIVACY & LEGAL (no URLs yet) are left out until
/// there is an account and the links exist. AI & PRIVACY says what goes
/// to the AI providers, holds the mood switch and withdraws consent
/// (#151). A TestFlight install adds a TESTING card: the photo trigger's
/// switch (InstallSource).
struct SettingsView: View {
    var settings: AppSettings
    var consent: AIConsent = .shared
    /// The photo trigger's switch; nil hides the TESTING card.
    var photoTriggerOptIn: Binding<Bool>?
    var onBack: () -> Void = {}
    var onOpenAppearance: () -> Void = {}
    var onOpenLanguage: () -> Void = {}

    /// Turning the switch on waits for this confirmation.
    @State private var confirmingOptIn = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10.5) {
                SettingsEyebrow(text: "PREFERENCES", size: 12, tracking: 1.5)
                VStack(spacing: 0) {
                    row("Appearance", value: settings.appearance.title, action: onOpenAppearance)
                        .accessibilityIdentifier("settings.appearance")
                    divider
                    row("Language", value: settings.language.title, action: onOpenLanguage)
                        .accessibilityIdentifier("settings.language")
                    divider
                    TextSizeControl(settings: settings)
                }
                .padding(.horizontal, 19)
                .settingsCard()

                SettingsEyebrow(text: "AI & PRIVACY", size: 12, tracking: 1.5)
                    .padding(.top, 21)
                AIPrivacyCard(consent: consent)
                    .padding(.horizontal, 19)
                    .settingsCard()

                if let photoTriggerOptIn {
                    SettingsEyebrow(text: "TESTING", size: 12, tracking: 1.5)
                        .padding(.top, 21)
                    PhotoTriggerOptInCard(isOn: photoTriggerOptIn, confirming: $confirmingOptIn)
                        .padding(.horizontal, 19)
                        .settingsCard()
                }
            }
            .padding(.horizontal, SettingsStyle.inset)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsHeader(title: "Settings", onBack: onBack)
        }
        // Photos leave the phone only after this says so (review of iOS#172).
        .alert("Turn on photo memories?", isPresented: $confirmingOptIn) {
            Button("Cancel", role: .cancel) {}
            Button("Turn On") { photoTriggerOptIn?.wrappedValue = true }
        } message: {
            Text("""
            MiraNote will look through your recent photos on this iPhone. For each moment it considers, it \
            sends up to 10 photos, with when and roughly where they were taken and what is in them, to our \
            server and an AI service that writes the reminder. This is a test feature.
            """)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    /// A 60 pt row: SemiBold 16 label, then the Medium 14 value and a 16 pt
    /// chevron, 8 apart.
    private func row(_ label: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(Sans.font(size: 16, weight: 600))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(Sans.font(size: 14, weight: 500))
                    .foregroundStyle(SettingsStyle.value)
                Image("row.chevron")
                    .renderingMode(.template)
                    .foregroundStyle(SettingsStyle.value)
                    .frame(width: 16, height: 16)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
    }
}

/// What is sent and to whom (the consent sheet's own lines), "Mood from my
/// words", and withdrawing consent. Turning the mood on before consent
/// asks first, with the sheet.
private struct AIPrivacyCard: View {
    var consent: AIConsent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AIDataSummary()
                .padding(.top, 16)
            AIDataDetails(idPrefix: "settings.ai")
                .padding(.vertical, 4)
            divider
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { consent.allowsMood }, set: setMood)) {
                    Text("Mood from my words")
                        .font(Sans.font(size: 16, weight: 600))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.forest)
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.moodFromWords")
                note("Off: saved pages are not read for a mood, and their stars stay one neutral color.")
            }
            .padding(.vertical, 12)
            divider
            VStack(alignment: .leading, spacing: 6) {
                if consent.isGranted {
                    Button("Stop sending to AI") { consent.withdraw() }
                        .font(Sans.font(size: 16, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.aiWithdraw")
                    note("Mira will ask again before the next AI action.")
                } else {
                    Button("Turn on AI features") { Task { _ = await consent.permit() } }
                        .font(Sans.font(size: 16, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.aiAllow")
                    note("Mira asks before anything is sent.")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Sans.font(size: 13, weight: 500))
            .lineSpacing(AIDataLines.spacing(for: 13))
            .foregroundStyle(SettingsStyle.value)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func setMood(_ on: Bool) {
        guard on else { return consent.moodFromWords = false }
        guard !consent.isGranted else { return consent.moodFromWords = true }
        Task { if await consent.permit() { consent.moodFromWords = true } }
    }
}

/// The photo trigger's switch and what turning it on does. Off to on asks
/// first (`confirming`); on to off takes effect at once.
private struct PhotoTriggerOptInCard: View {
    @Binding var isOn: Bool
    @Binding var confirming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { isOn }, set: { if $0 { confirming = true } else { isOn = false } })) {
                Text("Photo memories (beta)")
                    .font(Sans.font(size: 16, weight: 600))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.forest)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.photoTrigger")
            Text("""
            When on, MiraNote looks through your recent photos and sends some of them to an AI service \
            to write memory reminders.
            """)
                .font(Sans.font(size: 13, weight: 500))
                .foregroundStyle(SettingsStyle.value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// "Text size" over a small "A", the slider and a large "A". The handoff's
/// rail (4 pt, #D8D5CA) fills in ink up to an 18 pt paper thumb with a 2 pt
/// ink ring. Steps of 5% from 80% to 125%; VoiceOver adjusts it by swiping.
/// The app's type follows it at once, this screen's too (`TextScale`).
private struct TextSizeControl: View {
    var settings: AppSettings

    private var range: ClosedRange<Double> { AppSettings.textScaleRange }
    private var fraction: Double {
        (settings.textScale - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text size")
                .font(Sans.font(size: 16, weight: 600))
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 20)
            // The two "A"s are the rail's end marks, not copy: unscaled, so
            // the rail keeps its length under the finger while the scale
            // changes.
            HStack(spacing: 20) {
                Text("A")
                    .font(Sans.font(size: 14, weight: 500, scaled: false))
                    .foregroundStyle(SettingsStyle.value)
                slider
                Text("A")
                    .font(Sans.font(size: 23, weight: 600, scaled: false))
                    .foregroundStyle(Palette.ink)
            }
            .frame(height: 34)
        }
        .padding(.top, 15)
        .padding(.bottom, 19)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue("\(Int((settings.textScale * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settings.setTextScale(settings.textScale + AppSettings.textScaleStep)
            case .decrement: settings.setTextScale(settings.textScale - AppSettings.textScaleStep)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("settings.textSize")
    }

    private var slider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline).frame(height: 4)
                Capsule().fill(Palette.ink).frame(width: thumbX, height: 4)
                Circle()
                    .fill(Palette.warmWhite)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .offset(x: thumbX - 9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -9))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let picked = range.lowerBound
                        + Double(drag.location.x / max(width, 1)) * (range.upperBound - range.lowerBound)
                    let stepped = (picked / AppSettings.textScaleStep).rounded() * AppSettings.textScaleStep
                    if abs(stepped - settings.textScale) > 0.001 { settings.setTextScale(stepped) }
                }
            )
        }
        .frame(height: 26)
    }
}
