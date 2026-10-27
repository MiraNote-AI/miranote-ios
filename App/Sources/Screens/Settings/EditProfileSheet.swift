import ImageIO
import MiraNoteKit
import PhotosUI
import SwiftUI

/// Handoff screen 07: the Edit Profile bottom sheet -- grabber, title and
/// close X, the Change avatar row (system photo picker), the Display Name
/// field and Save changes. Save writes and closes; the X, a tap on the
/// scrim or a drag down closes without saving. A name is required (trimmed,
/// at most 40 characters) and Save waits until something changed.
///
/// Drawn by hand, not a system sheet: the handoff's sheet sits flush with
/// the screen's sides and bottom, which a short system sheet does not.
struct EditProfileSheet: View {
    var profile: LocalProfile
    /// The saved avatar, shown until a new photo is picked.
    let avatar: UIImage?
    var onClose: () -> Void

    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var newAvatar: (image: UIImage, data: Data)?
    @State private var loadingPhoto = false
    @State private var problem: String?
    @FocusState private var nameFocused: Bool
    @State private var drag: CGFloat = 0
    /// The name was changed in this sheet (an empty one then says why
    /// Save is off).
    @State private var nameEdited = false

    private var canSave: Bool {
        !loadingPhoto && profile.canSave(name: name, hasNewAvatar: newAvatar != nil)
    }

    private var helper: String {
        if let problem { return problem }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nameEdited, trimmed.isEmpty { return "Name can't be empty." }
        if trimmed.count > LocalProfile.nameLimit {
            return "Use \(LocalProfile.nameLimit) characters or fewer."
        }
        return "Your name appears on your profile."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xC7C0B4))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityHidden(true)

            HStack(alignment: .top) {
                Text("Edit Profile")
                    .font(Sans.font(size: 23, weight: 600))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 5)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Image("sheet.close")
                        .renderingMode(.template)
                        .foregroundStyle(SettingsStyle.intro)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(hex: 0xF1EEE6)))
                }
                .buttonStyle(.plain)
                .padding(7)
                .contentShape(Rectangle())
                .padding(-7)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("profile.sheet.close")
            }
            .padding(.top, 15)
            .padding(.trailing, -6)

            avatarRow
                .padding(.top, 23)

            Rectangle()
                .fill(Color(hex: 0xD8D5C9))
                .frame(height: 1)
                .padding(.top, 16)

            Text("Display Name")
                .font(Sans.font(size: 15, weight: 600))
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 22)
                .padding(.top, 16)

            nameField
                .padding(.top, 9)

            Text(helper)
                .font(Sans.font(size: 13, weight: 500))
                .foregroundStyle(SettingsStyle.note)
                .frame(minHeight: 20)
                .padding(.top, 13)
                .accessibilityIdentifier("profile.sheet.helper")

            Button(action: save) {
                Text("Save changes")
                    .font(Sans.font(size: 17, weight: 600))
                    .foregroundStyle(Color(hex: 0xFFFAF3))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            // Off still reads: its label at 5.1:1 (at 0.45 it read 2.8:1).
            .opacity(canSave ? 1 : 0.65)
            .accessibilityIdentifier("profile.sheet.save")
            .padding(.top, 16.5)
        }
        .padding(.horizontal, 26)
        // Save ends 16 above the home indicator's band (screen 07).
        .padding(.bottom, 16)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color(hex: 0xFFFCF5))
                .ignoresSafeArea(.container, edges: .bottom)
        )
        .offset(y: drag)
        .gesture(
            DragGesture()
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 80 {
                        onClose()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { drag = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            name = profile.displayName
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onChange(of: pickerItem) { load(pickerItem) }
        .onChange(of: name) { old, new in
            problem = nil
            // Any change but the saved name filled in on appear.
            if !(old.isEmpty && new == profile.displayName) { nameEdited = true }
        }
    }

    /// The 64 pt avatar and "Change avatar" over its helper, 20 apart; the
    /// whole row opens the photo picker.
    private var avatarRow: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: 20) {
                ProfileAvatar(image: newAvatar?.image ?? avatar, size: 64, glyph: 36)
                    .overlay {
                        if loadingPhoto { ProgressView().tint(Palette.ink) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Change avatar")
                        .font(Sans.font(size: 17, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 25)
                    Text("Choose a photo from your device")
                        .font(Sans.font(size: 13, weight: 500))
                        .foregroundStyle(SettingsStyle.note)
                        .frame(minHeight: 21)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Change avatar")
        .accessibilityHint("Choose a photo from your device")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("profile.sheet.avatar")
    }

    /// 54 pt, r14, #F6F4EF with a #D8D5C9 hairline: Medium 16 text 16 in,
    /// the pencil 21 from the right.
    private var nameField: some View {
        HStack(spacing: 8) {
            TextField("Add your name", text: $name)
                .font(Sans.font(size: 16, weight: 500))
                .foregroundStyle(Palette.ink)
                .tint(Palette.ink)
                .focused($nameFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Display Name")
                .accessibilityIdentifier("profile.sheet.name")
            Image("field.pencil")
                .renderingMode(.template)
                .foregroundStyle(SettingsStyle.eyebrow)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 21)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: 0xF6F4EF))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: 0xD8D5C9), lineWidth: 1))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { nameFocused = true }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        problem = nil
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            let avatar = await Task.detached(priority: .userInitiated) {
                data.flatMap(Self.avatar(from:))
            }.value
            // A later pick took over while this one loaded.
            guard pickerItem == item else { return }
            if let avatar {
                newAvatar = (UIImage(cgImage: avatar.image), avatar.png)
            } else {
                problem = "That photo could not be opened. Try another one."
            }
            loadingPhoto = false
        }
    }

    /// The photo at most 512 px (the largest avatar is drawn 76 pt),
    /// upright, and its PNG -- what the profile stores. ImageIO decodes
    /// only the thumbnail, off the main thread: a 48 MP photo never is.
    private nonisolated static func avatar(from data: Data) -> (image: CGImage, png: Data)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = UIImage(cgImage: image).pngData() else { return nil }
        return (image, png)
    }

    private func save() {
        do {
            try profile.save(name: name, avatar: newAvatar?.data)
            onClose()
        } catch {
            problem = "Your changes could not be saved. Try again."
        }
    }
}
