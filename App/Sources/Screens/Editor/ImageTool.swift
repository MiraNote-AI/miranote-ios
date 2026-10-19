import MiraNoteKit
import PhotosUI
import SwiftUI

/// A made sticker the user has picked but not yet placed. The Sticker panel
/// hands it back to the canvas, where the next tap on the paper decides where
/// it lands -- on a tall journal, the page bottom meant scrolling down to find
/// it and dragging all the way back up.
struct PendingPlacement: Equatable {
    let prompt: String
    let fileName: String
    let isSticker: Bool
    /// Where it lands, in page points, when the placement flow picks the
    /// spot itself (`UIVariant.placeFlow`); nil asks for a tap.
    var at: CGPoint?
}

/// Where the Image tool stands. It opens in place over the live canvas
/// (handoff screens 23-29), so placed photos land on the page the user is
/// looking at and stay editable there.
enum ImagePhase: Equatable {
    /// "Choose photos": Photo Library / Camera / AI Image (screen 23).
    case choose
    /// The in-sheet Recents grid (screens 24, 26).
    case library
    /// AI Image: the composer takes words, the sheet shows the paintings.
    case generate
    /// Photos placed with the tool still open (screens 25, 29): Cancel takes
    /// them back, Add keeps them.
    case placed
}

/// Saves picked or captured photos and puts them on the page: aspect-true
/// boxes that sway left-center-right as they stack, each one a step of its
/// own, each looked at once by vision in the background.
@MainActor
struct PhotoPlacer {
    let editor: CanvasViewModel
    let studio: ImageStudioService
    private let imageStore = ImageFileStore()

    init(editor: CanvasViewModel, studio: ImageStudioService) {
        self.editor = editor
        self.studio = studio
    }

    /// The placed photo's id; nil when its bytes could not be stored.
    @discardableResult
    func place(_ imageData: Data, name: String) -> CanvasItem.ID? {
        guard let fileName = try? imageStore.save(imageData, id: UUID()) else { return nil }
        // Deterministic on the existing photo count so tests stay stable.
        let photoCount = editor.items.filter {
            if case .image = $0.content { return true } else { return false }
        }.count
        let sway: CGFloat = [-28, 0, 28][photoCount % 3]
        // The box adopts the photo's aspect (within taste) so portrait
        // shots arrive tall instead of center-cropped into a landscape.
        var box = CGSize(width: 170, height: 150)
        if let ui = UIImage(data: imageData) {
            box = CanvasImageCache.aspectBox(for: ui)
        }
        let position = CGPoint(
            x: MiraNoteConfig.pageWidth / 2 + sway,
            y: min(editor.contentBottom + 60 + box.height / 2, 4000)
        )
        let id = editor.addImages(
            [ImageRef(displayName: name, fileName: fileName)], around: position, size: box
        ).first
        describeInBackground(itemID: id, imageData: imageData)
        return id
    }

    /// Library photos in pick order; the ids of those that landed.
    func place(_ photos: [Data]) -> [CanvasItem.ID] {
        photos.compactMap { place($0, name: "Library photo") }
    }

    /// The system picker's picks' bytes, downscaled for the canvas, in pick
    /// order (those that load).
    static func data(for items: [PhotosPickerItem]) async -> [Data] {
        var loaded: [Data] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let scaled = UIImage(data: data)?.downscaled() else { continue }
            loaded.append(scaled)
        }
        return loaded
    }

    /// Vision looks at the photo once, off the main path; the sentence
    /// becomes page context so chat can "see" the picture. Best-effort.
    private func describeInBackground(itemID: CanvasItem.ID?, imageData: Data) {
        guard let itemID else { return }
        let editor = self.editor
        let studio = self.studio
        Task {
            guard let summary = try? await studio.describe(image: imageData) else { return }
            editor.setImageSummary(itemID: itemID, to: summary)
        }
    }

    #if DEBUG
    /// -UITEST: two canned images straight through the real pipeline; the
    /// second is portrait so tests can lock aspect-true boxes and
    /// overflow-free rendering. -DEMO-SAMPLES (demo-video recorder, live
    /// services) places ONE painted photo big enough for a real cutout.
    func placeSamples() -> [CanvasItem.ID] {
        if ProcessInfo.processInfo.arguments.contains("-DEMO-SAMPLES") {
            return [place(Self.demoBowlPhoto(), name: "Noodle lunch")].compactMap { $0 }
        }
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 16)).pngData { context in
            UIColor(red: 0.79, green: 0.70, blue: 0.58, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        }
        return [
            place(MockImageStudioService.tinyPNG, name: "Sample one"),
            place(tall, name: "Sample two"),
        ].compactMap { $0 }
    }

    /// A warm bowl-of-noodles still life, painted at photo size so the
    /// live /cutout has a real subject to lift.
    private static func demoBowlPhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).pngData { context in
            let c = context.cgContext
            UIColor(red: 0.93, green: 0.88, blue: 0.80, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            UIColor(red: 0.77, green: 0.66, blue: 0.51, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 750, width: 900, height: 450))
            UIColor(red: 0.35, green: 0.23, blue: 0.16, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 240, y: 620, width: 420, height: 300))
            UIColor(red: 0.89, green: 0.70, blue: 0.36, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 270, y: 640, width: 360, height: 190))
            UIColor(red: 0.96, green: 0.91, blue: 0.70, alpha: 1).setStroke()
            c.setLineWidth(7)
            for i in 0..<12 {
                let x = CGFloat(300 + i * 25)
                c.strokeEllipse(in: CGRect(x: x, y: 660, width: 60, height: 110))
            }
            UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 400, y: 590, width: 100, height: 100))
            UIColor(red: 0.93, green: 0.67, blue: 0.26, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 425, y: 615, width: 50, height: 50))
        }
    }
    #endif
}

// MARK: - Sheets

/// Screen 23: the "Choose photos" glass sheet over the canvas -- fixed
/// 94.55 x 30 pills, Photo Library filled ink. The third pill paints an AI
/// image (owner, 2026-10-18); stickers stay the fifth tool.
struct ChoosePhotosSheet: View {
    var notice: String?
    var onLibrary: () -> Void
    var onCamera: () -> Void
    var onGenerate: () -> Void
    var onSamples: () -> Void

    var body: some View {
        GlassSheet(
            title: "Choose photos",
            // The design's "imported media, or a link" names sources the
            // app does not have.
            subtitle: "Start from camera roll, camera, or AI.",
            titleSize: 20
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5.67) {
                    pill("Photo Library", filled: true, id: "image.library.open", action: onLibrary)
                    pill("Camera", filled: false, id: "image.camera.open", action: onCamera)
                    pill("AI Image", filled: false, id: "image.source.generate", action: onGenerate)
                }
                #if DEBUG
                if (ProcessInfo.processInfo.arguments.contains("-UITEST")
                    || ProcessInfo.processInfo.arguments.contains("-DEMO-SAMPLES")) && !UIVariant.ownerShots {
                    pill("Samples", filled: false, id: "image.library.samples", action: onSamples)
                }
                #endif
                if let notice {
                    Text(notice)
                        .font(.miraComposer)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("image.notice")
                }
            }
        }
    }

    private func pill(_ label: String, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(filled ? Palette.onInk : Palette.ink)
                .frame(width: 94.55, height: 30)
                .background(Capsule().fill(filled ? Palette.ink : Palette.paper))
                .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Screens 24 and 26: the Recents sheet -- the newest library photos in
/// the design's 3-column grid of r18 cells, picks ringed in ink with their
/// order. The header counts the picks, or offers "Editing" for a single one.
/// Without photo access it says so and offers Settings or the system picker.
struct RecentsSheet: View {
    let library: RecentPhotos
    @Binding var selection: [LibraryPhoto]
    /// The picks are importing: Editing waits.
    var importing: Bool
    var onEditing: () -> Void
    /// Photos picked through the system picker (no library access).
    var onSystemPicks: ([PhotosPickerItem]) -> Void

    @State private var systemPicks: [PhotosPickerItem] = []
    @State private var gridWidth: CGFloat = 298
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        GlassSheet(fillOpacity: 0.5, elevation: .raised) {
            VStack(alignment: .leading, spacing: 20) {
                header
                switch library.access {
                case .unknown:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 284)
                case .denied:
                    denied
                        .frame(height: 284, alignment: .top)
                case .granted:
                    grid
                case .limited:
                    VStack(alignment: .leading, spacing: 12) {
                        limitedBar
                        grid
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .task { if library.access == .unknown { await library.load() } }
        .onChange(of: systemPicks) { _, picks in
            guard !picks.isEmpty else { return }
            onSystemPicks(picks)
            systemPicks = []
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(library.photos.enumerated()), id: \.element) { index, photo in
                    RecentCell(library: library, photo: photo, order: order(of: photo))
                        .onTapGesture { toggle(photo) }
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(order(of: photo) != nil ? .isSelected : [])
                        .accessibilityLabel("Photo \(index + 1)")
                        .accessibilityIdentifier("image.library.photo.\(index)")
                }
            }
        }
        // Three full rows show, as drawn (284 on the design's 298-wide grid).
        .frame(height: 3 * ((gridWidth - 20) / 3 * 88 / 92) + 20)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .padding(.leading, 1)
        .accessibilityIdentifier("image.library.grid")
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MiraNote can't see your photos. Allow access in Settings, or pick a few here.")
                .font(.miraComposer)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: 8) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(NavPill(prominent: true))
                systemPicker
            }
        }
    }

    /// Limited access: the grid holds only the photos the user shared, so
    /// the sheet offers the others -- share more (the system's limited
    /// picker; the grid follows), or pick a few once.
    private var limitedBar: some View {
        HStack(spacing: 8) {
            Text("Only the photos you shared show here.")
                .font(.miraComposer)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Share more", action: library.shareMorePhotos)
                .buttonStyle(NavPill(prominent: true))
                .accessibilityIdentifier("image.library.more")
            systemPicker
        }
    }

    /// The system photo picker: any photo, without library access.
    private var systemPicker: some View {
        PhotosPicker(
            selection: $systemPicks,
            maxSelectionCount: MiraNoteConfig.maxImagesPerAdd,
            matching: .images
        ) {
            Text("Pick photos")
        }
        .buttonStyle(NavPill(prominent: false))
        .accessibilityIdentifier("image.library.system")
    }

    private func order(of photo: LibraryPhoto) -> Int? {
        selection.firstIndex(of: photo).map { $0 + 1 }
    }

    private func toggle(_ photo: LibraryPhoto) {
        if let index = selection.firstIndex(of: photo) {
            selection.remove(at: index)
        } else if selection.count < MiraNoteConfig.maxImagesPerAdd {
            selection.append(photo)
        }
    }

    private var header: some View {
        HStack {
            Text("Recents")
                .font(Sans.font(size: 18, weight: 700))
                .foregroundStyle(Palette.ink)
            Spacer()
            if selection.count == 1 {
                Button("Editing", action: onEditing)
                    .buttonStyle(NavPill(prominent: false, width: NavPill.leadingWidth))
                    .disabled(importing)
                    .opacity(importing ? 0.35 : 1)
                    .accessibilityIdentifier("image.library.editing")
            } else if selection.count > 1 {
                Text("\(selection.count) selected")
                    .font(Sans.font(size: 12, weight: 700))
                    .foregroundStyle(Palette.forest)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("image.library.count")
            }
        }
        .frame(height: 22)
    }
}

/// One Recents cell: 92 x 88 r18 on the design's 374 pt screen (wider
/// phones widen it at the same aspect); a pick wears a 3 pt ink ring and a
/// 22 pt ink badge with its order at the top right.
private struct RecentCell: View {
    let library: RecentPhotos
    let photo: LibraryPhoto
    let order: Int?

    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.imageCorner)
        Color.clear
            .aspectRatio(92.0 / 88.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    GradientPlaceholder()
                }
            }
            .clipShape(shape)
            .overlay {
                if order != nil { shape.strokeBorder(Palette.ink, lineWidth: 3) }
            }
            .overlay(alignment: .topTrailing) {
                if let order {
                    Text("\(order)")
                        .font(Sans.font(size: 10, weight: 700))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Palette.ink))
                        .padding(5)
                }
            }
            .contentShape(shape)
            .task(id: photo) { image = await library.thumbnail(photo, side: 92) }
    }
}
