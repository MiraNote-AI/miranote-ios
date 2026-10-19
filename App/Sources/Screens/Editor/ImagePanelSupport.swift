import MiraNoteKit
import SwiftUI
import UIKit

/// Minimal camera bridge; unavailable in the simulator.
struct CameraCapture: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

/// The Image and Sticker panels show the page read-only in the canvas card
/// above their sheets; a tap on it returns to the canvas. Only the page
/// counts, not the margins beside it. The tap is read on the full-width row
/// and tested by position: a gesture on the page alone also fired from the
/// margins (touch slop hands a near-miss to the nearest tappable view).
struct PagePreview: View {
    let memory: Memory
    /// Where the canvas stood: the preview opens on the same part of the page.
    var scroll = CanvasScrollMemory()
    var onTapPage: () -> Void

    private static let topID = "preview.top"

    var body: some View {
        GeometryReader { geo in
            // The page scales up to fill the card, as on the canvas.
            let cardWidth = geo.size.width - 2 * Metrics.canvasInset
            let scale = cardWidth / MiraNoteConfig.pageWidth
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        StaticPageView(memory: memory, showsSound: false)
                            .scaleEffect(scale, anchor: .topLeading)
                        // The canvas's scroll position, as a spot to scroll to.
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id(Self.topID)
                            .padding(.top, scroll.offset * scale)
                    }
                    .frame(
                        width: cardWidth,
                        height: max(StaticPageView.contentHeight(of: memory), geo.size.height / scale + scroll.offset)
                            * scale,
                        alignment: .topLeading
                    )
                }
                .onAppear {
                    guard scroll.offset > 0 else { return }
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
            .canvasCard()
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let left = (geo.size.width - cardWidth) / 2
                guard point.x >= left, point.x <= left + cardWidth else { return }
                onTapPage()
            }
        }
    }
}
