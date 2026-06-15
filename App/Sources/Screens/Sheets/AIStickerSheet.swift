import MiraNoteKit
import SwiftUI

/// Sketch 2.2 entry one (split per D2): describe a sticker, generate,
/// place it on the canvas.
struct AIStickerSheet: View {
    @State private var viewModel: AIStickerViewModel
    @Environment(\.dismiss) private var dismiss
    let onAdd: (GeneratedSticker) -> Void

    init(services: ServiceContainer, onAdd: @escaping (GeneratedSticker) -> Void) {
        _viewModel = State(initialValue: AIStickerViewModel(
            service: services.stickerGeneration,
            voiceService: services.voiceTranscription
        ))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    TextField("Describe a sticker", text: $viewModel.prompt)
                        .textFieldStyle(.roundedBorder)
                    // A3: same voice glyph as the Home pill; dictates into
                    // the prompt field.
                    Button {
                        Task { await viewModel.toggleDictation() }
                    } label: {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.badge.plus")
                    }
                    .tint(viewModel.isRecording ? .red : nil)
                    .disabled(viewModel.isGenerating)
                }

                if let sticker = viewModel.generated {
                    VStack(spacing: 12) {
                        Image(systemName: sticker.symbolName)
                            .font(.system(size: 64))
                        Text(sticker.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Add to canvas") {
                            onAdd(sticker)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await viewModel.generate() }
                } label: {
                    if viewModel.isGenerating {
                        ProgressView()
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(!viewModel.canGenerate)
            }
            .padding()
            .navigationTitle("AI Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    AIStickerSheet(services: .mock) { _ in }
}
