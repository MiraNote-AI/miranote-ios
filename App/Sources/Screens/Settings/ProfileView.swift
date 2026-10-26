import MiraNoteKit
import SwiftUI

/// Handoff screen 06: the identity card -- avatar with its camera badge,
/// display name, hint and Edit Profile. Avatar, name and the button open
/// the Edit Profile sheet (screen 07). ACCOUNT DETAILS (email) and YOUR
/// SPACE (Sticker Library, Subscription) are left out until there is an
/// account and those screens exist.
struct ProfileView: View {
    var profile: LocalProfile
    var onBack: () -> Void = {}

    @Environment(\.theme) private var theme
    @State private var editing = false
    @State private var avatar: UIImage?

    var body: some View {
        ScrollView(showsIndicators: false) {
            identityCard
                .padding(.horizontal, SettingsStyle.inset)
                .padding(.top, 24)
                .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsHeader(title: "Profile", onBack: onBack)
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if editing {
                    // The handoff's modal scrim: #201E1C at 38%.
                    Color(hex: 0x201E1C).opacity(0.38)
                        .ignoresSafeArea()
                        .onTapGesture { editing = false }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    EditProfileSheet(profile: profile, avatar: avatar) { editing = false }
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.25), value: editing)
        }
        .task(id: profile.avatarFileName) {
            avatar = profile.loadAvatar().flatMap(UIImage.init(data:))
        }
    }

    /// 342 wide: the 76 pt avatar 17 from the top, the name (SemiBold 23)
    /// 18 under it, the hint (Medium 13) and the 46 pt ink button 18 in
    /// from the card's sides and bottom.
    private var identityCard: some View {
        VStack(spacing: 0) {
            Button { editing = true } label: {
                ProfileAvatar(image: avatar, size: 76, glyph: 44)
                    .overlay(alignment: .topLeading) {
                        Image("profile.camera")
                            .renderingMode(.template)
                            .foregroundStyle(SettingsStyle.intro)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(hex: 0xFFFCF5))
                                    .overlay(Circle().strokeBorder(Color(hex: 0xD8D5C9), lineWidth: 1))
                            )
                            .offset(x: 59, y: 58)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change avatar")
            .accessibilityIdentifier("profile.avatar")
            .padding(.top, 17)

            Button { editing = true } label: {
                Text(profile.displayName.isEmpty ? "Add your name" : profile.displayName)
                    .font(Sans.font(size: 23, weight: 600))
                    .foregroundStyle(profile.displayName.isEmpty ? SettingsStyle.note : Palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 28)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Edit Profile")
            .accessibilityIdentifier("profile.name")
            .padding(.top, 16)
            .padding(.horizontal, 28)

            Text("Tap your avatar or name to edit")
                .font(Sans.font(size: 13, weight: 500))
                .foregroundStyle(SettingsStyle.note)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
                .padding(.top, 3.5)
                .padding(.horizontal, 28)
                .accessibilityHidden(true)

            Button { editing = true } label: {
                Text("Edit Profile")
                    .font(Sans.font(size: 17, weight: 600))
                    .foregroundStyle(theme.onButton(Color(hex: 0xFFFAF3)))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(theme.button))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.edit")
            .padding(.top, 19.5)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .settingsCard()
    }
}

/// The handoff's avatar: a #E8D7C4 disc with a #D3C4B0 ring and the
/// person glyph (Home's profile glyph scaled up), or the saved photo.
struct ProfileAvatar: View {
    let image: UIImage?
    let size: CGFloat
    /// The person glyph's frame: 44 on the 76 pt avatar, 36 on 64.
    let glyph: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("home.profile")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(SettingsStyle.intro)
                    .frame(width: glyph, height: glyph)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0xE8D7C4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(hex: 0xD3C4B0), lineWidth: 1))
    }
}
