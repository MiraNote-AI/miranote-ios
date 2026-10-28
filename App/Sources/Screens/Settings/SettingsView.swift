import MiraNoteKit
import SwiftUI

/// Handoff screen 03: the PREFERENCES card -- Appearance and Language rows
/// with their current values, and the text-size slider. The ACCOUNT card
/// (email, Log Out) and PRIVACY & LEGAL (no URLs yet) are left out until
/// there is an account and the links exist.
struct SettingsView: View {
    var settings: AppSettings
    var onBack: () -> Void = {}
    var onOpenAppearance: () -> Void = {}
    var onOpenLanguage: () -> Void = {}

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
            }
            .padding(.horizontal, SettingsStyle.inset)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsHeader(title: "Settings", onBack: onBack)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    /// A 60 pt row: SemiBold 16 label, then the Medium 14 value and a 16 pt
    /// chevron, 8 apart.
    private func row(_ label: String, value: String, action: @escaping () -> Void) -> some View {
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

/// "Text size" over a small "A", the slider and a large "A". The handoff's
/// rail (4 pt, #D8D5CA) fills in ink up to an 18 pt paper thumb with a 2 pt
/// ink ring. Steps of 5% from 80% to 125%; VoiceOver adjusts it by swiping.
/// The scale is a persisted preference: the app's type is fixed-size
/// (Typography.swift has no scale to hook), so applying it is a follow-up.
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
            HStack(spacing: 20) {
                Text("A")
                    .font(Sans.font(size: 14, weight: 500))
                    .foregroundStyle(SettingsStyle.value)
                slider
                Text("A")
                    .font(Sans.font(size: 23, weight: 600))
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
