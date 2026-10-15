import MiraNoteKit
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reading mode (v2.1): the finished page, full bleed -- where looking
/// happens, where sound plays, and where the share/export entry lives.
/// Editing is one tap away.
struct ReadingView: View {
    let memory: Memory
    var onBack: () -> Void = {}
    var onEdit: () -> Void = {}
    var photoSaver: PhotoSaver = .library

    @State private var player = SoundPlayer()
    @State private var showsExport = false
    @State private var toast: SaveToast.Message?
    @State private var toastDismiss: Task<Void, Never>?

    var body: some View {
        ScrollView(showsIndicators: false) {
            StaticPageView(memory: memory, designWidth: MiraNoteConfig.pageWidth, player: player)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                circleButton("chevron.left", id: "reading.back", action: onBack)
                Spacer()
                Text(memory.title)
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer()
                circleButton("square.and.arrow.up", id: "reading.share") { setExport(open: !showsExport) }
                circleButton("pencil", id: "reading.edit", action: onEdit)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
            .background(Palette.paper.opacity(0.94))
        }
        .overlay {
            // Screen 37 draws the sheet over the live page, no scrim: a tap
            // on the page around it closes it.
            if showsExport {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setExport(open: false) }
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if let toast {
                    SaveToast(message: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showsExport {
                    ExportSheet(
                        memory: memory,
                        photoSaver: photoSaver,
                        onClose: { setExport(open: false) },
                        onSaved: saved
                    )
                    // The screen's width, not the page's: the reading page is
                    // wider than a 390 pt phone, and padding it would push
                    // the sheet off the chrome inset.
                    .containerRelativeFrame(.horizontal) { width, _ in width - 2 * Metrics.chromeInset }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // The sheet's foot sits 42 above the screen edge, as drawn.
            .padding(.bottom, 8)
        }
        .onDisappear { player.stop() }
    }

    private func setExport(open: Bool) {
        withAnimation(.spring(duration: 0.3)) { showsExport = open }
    }

    /// Screen 38: a saved page closes the sheet and says where it went; a
    /// failed one keeps the sheet up to try again (or the other way).
    private func saved(_ message: SaveToast.Message) {
        if message != .failed { setExport(open: false) }
        toastDismiss?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = message }
        toastDismiss = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    private func circleButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Palette.onInk)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Where Save to Photos puts the encoded bytes. UI tests swap in a stub so
/// no Photos permission prompt is involved.
struct PhotoSaver {
    var save: (Data) async -> Bool

    /// The bytes go in as they are, so a PNG export stays a PNG and a JPG a
    /// JPG (going through UIImage would re-encode either).
    static let library = PhotoSaver { data in
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { succeeded, _ in
                continuation.resume(returning: succeeded)
            })
        }
    }
}

/// The four tiles of the export sheet's format row (screen 37). Print is
/// not a file format: it sends A4 pages to a printer.
enum ExportTile: String, CaseIterable, Identifiable {
    case png, pdf, jpg, print

    var id: String { rawValue }
    var label: String { self == .print ? "Print" : rawValue.uppercased() }

    var format: ExportFormat? {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .jpg: return .jpg
        case .print: return nil
        }
    }
}

/// Handoff screen 37, in the scene rather than a system sheet: a raised
/// glass sheet over the page with the format tiles (PNG, PDF, JPG, Print),
/// the quality pills (Standard, High, Original), and Save to Photos / Save
/// to Files. A PDF also chooses one long page or A4 pages; Share sits in
/// the header. A page with sound says plainly that audio stays in the app.
struct ExportSheet: View {
    let memory: Memory
    var photoSaver: PhotoSaver
    var onClose: () -> Void
    var onSaved: (SaveToast.Message) -> Void

    @State private var tile: ExportTile = .png
    @State private var quality: ExportQuality = .high
    @State private var pdfLayout: PDFLayout = .a4Pages
    @State private var rendered: UIImage?
    @State private var savingToFiles = false
    /// This sheet's own temp folder for the Share file.
    @State private var exportFolder = "export-\(UUID().uuidString)"

    /// The bytes for the chosen format, and the same bytes as a named file
    /// for Share. Rebuilt only when the render, format or layout changes --
    /// a PDF is too costly to remake on every view update.
    @State private var exportData: Data?
    @State private var shareURL: URL?
    /// Bumps per option change; a slower earlier encode must not land last.
    @State private var exportGeneration = 0

    /// The file format the bytes are in; Print reuses the PNG render.
    private var format: ExportFormat { tile.format ?? .png }
    private var fileName: String { PageExporter.fileName(title: memory.title, format: format) }

    private var hasSound: Bool {
        memory.items.contains { if case .sound = $0.content { return true } else { return false } }
    }

    var body: some View {
        // Sheet-relative frames from the handoff: title (21, 19), line 51,
        // tiles 81, "Quality" 153, pills 175, actions 223, foot 272.
        GlassSheet(titleSize: 20, elevation: .raised, bottomPadding: 11) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Export & Save")
                    .font(Sans.font(size: 20, weight: 700))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) { shareButton }
                    .padding(.top, 2)
                Text("Choose format and quality before saving.")
                    .font(Sans.font(size: 12, weight: 500))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)
                tiles
                    .padding(.top, 16)
                Text("Quality")
                    .font(Sans.font(size: 12, weight: 500))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 20)
                pills(ExportQuality.allCases, selected: quality, id: "export.quality") { quality = $0 }
                    .padding(.top, 8)
                if tile == .pdf {
                    pills(PDFLayout.allCases, selected: pdfLayout, id: "export.pdf") { pdfLayout = $0 }
                        .padding(.top, 10)
                }
                actions
                    .padding(.top, 16)
                if hasSound {
                    Label {
                        Text("This page's sound plays in MiraNote only.")
                    } icon: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .font(Sans.font(size: 11, weight: 400))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 10)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.sheet")
        .accessibilityAction(.escape, onClose)
        .task { render() }
        // The share file is only needed while the sheet is up.
        .onDisappear { try? FileManager.default.removeItem(at: folderURL) }
        .onChange(of: quality) { render() }
        .onChange(of: tile) { refreshExport() }
        .onChange(of: pdfLayout) { refreshExport() }
        .fileExporter(
            isPresented: $savingToFiles,
            document: ExportDocument(data: exportData ?? Data()),
            contentType: format.contentType,
            defaultFilename: fileName
        ) { result in
            switch result {
            case .success:
                onSaved(.savedToFiles)
            case .failure(let error):
                // Backing out of the picker is not a failed save.
                if (error as? CocoaError)?.code != .userCancelled { onSaved(.failed) }
            }
        }
    }

    /// PNG, PDF, JPG, Print: 54 pt r18 tiles, ink when chosen, #ECE7D8
    /// otherwise.
    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(ExportTile.allCases) { option in
                Button {
                    tile = option
                } label: {
                    Text(option.label)
                        .font(Sans.font(size: 11, weight: 700))
                        .foregroundStyle(option == tile ? Palette.onInk : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(option == tile ? Palette.ink : Palette.cardFill)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == tile ? .isSelected : [])
                .accessibilityIdentifier("export.format.\(option.rawValue)")
            }
        }
    }

    /// A row of 32 pt pills: ink when chosen, white with a faint rim and
    /// the muted label otherwise.
    private func pills<Option: ExportOption>(
        _ options: [Option],
        selected: Option,
        id: String,
        choose: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ForEach(options) { option in
                Button {
                    choose(option)
                } label: {
                    Text(option.label)
                        .font(Sans.font(size: 11, weight: 700))
                        .foregroundStyle(option == selected ? Palette.onInk : Palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule()
                                .fill(option == selected ? Palette.ink : Color.white)
                                .overlay(Capsule().strokeBorder(Palette.ink.opacity(option == selected ? 0 : 0.05),
                                                                lineWidth: 1))
                        )
                        .contentShape(Capsule())
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selected ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(option.id)")
            }
        }
    }

    /// Save to Photos (ink) beside Save to Files (white); a PDF goes to
    /// Files only, which then takes the ink; Print is one ink button.
    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if tile == .print {
                action("Print", filled: true, id: "export.print", action: printPage)
                    .disabled(rendered == nil)
            } else {
                if format.savesToPhotos {
                    action("Save to Photos", filled: true, id: "export.photos", action: saveToPhotos)
                        .disabled(exportData == nil)
                }
                action("Save to Files", filled: !format.savesToPhotos, id: "export.files") { savingToFiles = true }
                    .disabled(exportData == nil)
            }
        }
    }

    private func action(_ title: String, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Sans.font(size: 12, weight: 700))
                .foregroundStyle(filled ? Palette.onInk : Palette.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(filled ? Palette.ink : Color.white))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Share stays one tap away, as a header glyph (the design draws no
    /// Share; the system sheet takes the named file).
    @ViewBuilder private var shareButton: some View {
        let glyph = Image(systemName: "square.and.arrow.up")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.7)))
        if let rendered, let shareURL, tile != .print {
            ShareLink(item: shareURL, preview: SharePreview(memory.title, image: Image(uiImage: rendered))) {
                glyph
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
            .accessibilityIdentifier("export.share")
        } else {
            glyph
                .opacity(0.4)
                .accessibilityLabel("Share")
                .accessibilityIdentifier("export.share")
        }
    }

    @MainActor private func render() {
        rendered = PageExporter.render(memory, quality: quality)
        refreshExport()
    }

    /// A folder per sheet, so two pages with one title never share a file.
    private var folderURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(exportFolder, isDirectory: true)
    }

    /// Re-encodes the render for the chosen format and writes it to a temp
    /// file named after the page, which is what Share hands to receivers.
    /// Off the main actor: a long page at High is tens of megabytes, and the
    /// tapped tile should highlight at once. The destinations stay disabled
    /// until the bytes are ready.
    private func refreshExport() {
        exportGeneration += 1
        let generation = exportGeneration
        exportData = nil
        shareURL = nil
        guard let rendered, tile != .print else { return }
        let format = format, layout = pdfLayout
        // A folder per encode: an older encode finishing last must not
        // overwrite the file Share hands out.
        let url = folderURL.appendingPathComponent("\(generation)", isDirectory: true)
            .appendingPathComponent(fileName)
        Task {
            let encoded = await Task.detached(priority: .userInitiated) { () -> (Data, URL?)? in
                guard let data = PageExporter.data(from: rendered, format: format, pdfLayout: layout) else { return nil }
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                return (data, (try? data.write(to: url, options: .atomic)) == nil ? nil : url)
            }.value
            guard generation == exportGeneration else { return }
            exportData = encoded?.0
            shareURL = encoded?.1
        }
    }

    private func saveToPhotos() {
        guard let exportData else { return }
        Task {
            let saved = await photoSaver.save(exportData)
            onSaved(saved ? .savedToPhotos : .failed)
        }
    }

    /// Printing always goes out as A4 pages: a printer cannot take one
    /// 4,000 pt sheet.
    private func printPage() {
        guard let rendered,
              let pages = PageExporter.data(from: rendered, format: .pdf, pdfLayout: .a4Pages) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = memory.title.isEmpty ? "MiraNote page" : memory.title
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pages
        controller.present(animated: true)
    }
}

/// The exported bytes as a document, for Save to Files. The type and name
/// come from the fileExporter call.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg, .pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
