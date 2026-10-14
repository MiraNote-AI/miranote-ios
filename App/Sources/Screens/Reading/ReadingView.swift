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

    @State private var player = SoundPlayer()
    @State private var showsExport = false

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
                circleButton("square.and.arrow.up", id: "reading.share") { showsExport = true }
                circleButton("pencil", id: "reading.edit", action: onEdit)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
            .background(Palette.paper.opacity(0.94))
        }
        .sheet(isPresented: $showsExport) {
            // Large too: with Advanced open the sheet outgrows the medium
            // detent on small phones.
            ExportSheet(memory: memory)
                .presentationDetents([.medium, .large])
        }
        .onDisappear { player.stop() }
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

/// The export sheet: destinations first (Save to Photos or Files, Share,
/// Print) and format, quality and PDF layout behind Advanced (redesign phase
/// C1, handoff screen 37). The page is always one long canvas; cutting it
/// into A4 pages is a PDF option. A page with sound says plainly that audio
/// stays in the app.
struct ExportSheet: View {
    let memory: Memory

    @State private var rendered: UIImage?
    @State private var format: ExportFormat = .png
    @State private var quality: ExportQuality = .standard
    @State private var pdfLayout: PDFLayout = .a4Pages
    @State private var advancedOpen = false
    @State private var confirmation: String?
    @State private var savingToFiles = false
    /// This sheet's own temp folder for the Share file.
    @State private var exportFolder = "export-\(UUID().uuidString)"
    @Environment(\.dismiss) private var dismiss

    private var hasSound: Bool {
        memory.items.contains { if case .sound = $0.content { return true } else { return false } }
    }

    /// The bytes for the chosen format, and the same bytes as a named file
    /// for Share. Rebuilt only when the render, format or layout changes --
    /// a PDF is too costly to remake on every view update.
    @State private var exportData: Data?
    @State private var shareURL: URL?
    /// Bumps per option change; a slower earlier encode must not land last.
    @State private var exportGeneration = 0

    private var fileName: String { PageExporter.fileName(title: memory.title, format: format) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share this page")
                .font(.miraPageTitle)
                .foregroundStyle(Palette.ink)

            HStack(alignment: .top, spacing: 14) {
                preview
                VStack(spacing: 8) {
                    if format.savesToPhotos {
                        Button {
                            saveToPhotos()
                        } label: {
                            destinationLabel("Save to Photos", filled: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(exportData == nil)
                        .accessibilityIdentifier("export.photos")
                    }

                    Button {
                        savingToFiles = true
                    } label: {
                        destinationLabel("Save to Files", filled: !format.savesToPhotos)
                    }
                    .buttonStyle(.plain)
                    .disabled(exportData == nil)
                    .accessibilityIdentifier("export.files")

                    shareButton

                    Button {
                        printPage()
                    } label: {
                        destinationLabel("Print", filled: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(rendered == nil)
                    .accessibilityIdentifier("export.print")

                    if hasSound {
                        Label {
                            Text("This page's sound plays in MiraNote only.")
                        } icon: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                    }
                    if let confirmation {
                        Text(confirmation)
                            .font(.miraCaption)
                            .foregroundStyle(Palette.forest)
                            .accessibilityIdentifier("export.confirmation")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Right under the destinations, not pinned to the sheet's bottom
            // edge: down there it sat in the home-indicator gesture zone and
            // taps missed it.
            Button {
                advancedOpen.toggle()
            } label: {
                HStack {
                    Image(systemName: advancedOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Advanced")
                    Spacer()
                    Text(summary)
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.advanced")

            if advancedOpen {
                advancedOptions
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .task { render() }
        // The share file is only needed while the sheet is up.
        .onDisappear { try? FileManager.default.removeItem(at: folderURL) }
        .onChange(of: quality) { render() }
        .onChange(of: format) { refreshExport() }
        .onChange(of: pdfLayout) { refreshExport() }
        .fileExporter(
            isPresented: $savingToFiles,
            document: ExportDocument(data: exportData ?? Data()),
            contentType: format.contentType,
            defaultFilename: fileName
        ) { result in
            if case .success = result { confirmation = "Saved to Files." }
        }
    }

    private var summary: String {
        let shape = format == .pdf ? pdfLayout.label : "Long image"
        return "\(shape) \u{00B7} \(format.label) \u{00B7} \(quality.label)"
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            optionRow("Format", ExportFormat.allCases, selected: format, id: "export.format") { format = $0 }
            if format == .pdf {
                optionRow("Pages", PDFLayout.allCases, selected: pdfLayout, id: "export.pdf") { pdfLayout = $0 }
            }
            optionRow("Quality", ExportQuality.allCases, selected: quality, id: "export.quality") { quality = $0 }
        }
    }

    private func optionRow<Option: ExportOption>(
        _ title: String,
        _ options: [Option],
        selected: Option,
        id: String,
        choose: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 56, alignment: .leading)
            ForEach(options) { option in
                Button {
                    choose(option)
                } label: {
                    Chip(text: option.label, selected: option == selected, compact: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selected ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(option.id)")
            }
            Spacer(minLength: 0)
        }
    }

    private var preview: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Palette.cardFill)
            }
        }
        .frame(width: 88, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    @ViewBuilder private var shareButton: some View {
        if let rendered, let shareURL {
            ShareLink(
                item: shareURL,
                preview: SharePreview(memory.title, image: Image(uiImage: rendered))
            ) {
                destinationLabel("Share...", filled: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.share")
        } else {
            destinationLabel("Share...", filled: false)
                .opacity(0.5)
        }
    }

    private func destinationLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.miraPill)
            .foregroundStyle(filled ? Palette.onInk : Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(filled ? Palette.ink : Palette.onInk)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
            )
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
    /// tapped chip should highlight at once. The destinations stay disabled
    /// until the bytes are ready.
    private func refreshExport() {
        exportGeneration += 1
        let generation = exportGeneration
        exportData = nil
        shareURL = nil
        guard let rendered else { return }
        let format = format, layout = pdfLayout
        let url = folderURL.appendingPathComponent(fileName)
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

    /// Hands Photos the encoded bytes as they are, so a PNG export stays a
    /// PNG and a JPG a JPG (going through UIImage would re-encode either).
    private func saveToPhotos() {
        guard let exportData else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: exportData, options: nil)
        }, completionHandler: { succeeded, _ in
            Task { @MainActor in
                confirmation = succeeded
                    ? "Saved to Photos."
                    : "Couldn't save -- allow Photos access in Settings."
            }
        })
    }

    /// Printing always goes out as A4 pages, whatever the export format: a
    /// printer cannot take one 4,000 pt sheet.
    private func printPage() {
        // Reuse the A4 PDF when that is what the sheet already built.
        let built = format == .pdf && pdfLayout == .a4Pages ? exportData : nil
        guard let rendered,
              let pages = built ?? PageExporter.data(from: rendered, format: .pdf, pdfLayout: .a4Pages) else { return }
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

