import MiraNoteKit
import SwiftUI
import UIKit

/// The Image panel's generate styles. All ride the api's art command with a
/// style-carrying prompt; stickers are made in the Sticker panel.
enum GenerateStyle: String, CaseIterable, Identifiable {
    case photo, illustration, watercolor

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    func fullPrompt(_ core: String) -> String {
        switch self {
        case .photo: return "a soft natural photograph of \(core)"
        case .illustration: return "a gentle storybook illustration of \(core)"
        case .watercolor: return "a light watercolor painting of \(core)"
        }
    }
}

/// A picture a panel generated, shown as a thumbnail until it is picked.
struct GeneratedResult: Identifiable {
    let id = UUID()
    let data: Data
    let prompt: String
}

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
    var onTapPage: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                StaticPageView(memory: memory, showsSound: false)
            }
            .canvasCard()
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let left = (geo.size.width - MiraNoteConfig.pageWidth) / 2
                guard point.x >= left, point.x <= left + MiraNoteConfig.pageWidth else { return }
                onTapPage()
            }
        }
    }
}
