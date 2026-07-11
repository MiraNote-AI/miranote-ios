import MiraNoteKit
import SwiftUI
import UIKit

/// v2.1 generate styles; sticker is just one of them. Photo / illustration /
/// watercolor ride the api's art command with a style-carrying prompt.
enum GenerateStyle: String, CaseIterable, Identifiable {
    case photo, illustration, watercolor, sticker

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var kind: GeneratedImageKind {
        self == .sticker ? .sticker : .art
    }

    func fullPrompt(_ core: String) -> String {
        switch self {
        case .photo: return "a soft natural photograph of \(core)"
        case .illustration: return "a gentle storybook illustration of \(core)"
        case .watercolor: return "a light watercolor painting of \(core)"
        case .sticker: return core
        }
    }
}

struct GeneratedResult: Identifiable {
    let id = UUID()
    let data: Data
    let prompt: String
    let style: GenerateStyle
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
