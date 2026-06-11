import MiraNoteKit
import PhotosUI
import SwiftUI

/// Sketch 2.2 entry two (split per D2): pick up to three images (D1),
/// choose a style, generate, add results to the canvas.
struct StyleTransferSheet: View {
    @State private var viewModel = StyleTransferViewModel()
    @State private var pickedItems: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([ImageRef]) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                imageRow

                Text("Style transfer")
                    .font(.headline)
                styleRow

                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let results = viewModel.results {
                    Button("Add \(results.count) styled image(s) to canvas") {
                        onAdd(results)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                HStack {
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
            }
            .padding()
            .navigationTitle("Style transfer")
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
            .onChange(of: pickedItems) { _, newItems in
                // v1 keeps display names only; pixel data handling is a
                // later task (see spec non-goals).
                let refs = newItems.indices.map { ImageRef(displayName: "Photo \($0 + 1)") }
                viewModel.addImages(refs)
                pickedItems = []
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.large])
    }

    private var imageRow: some View {
        HStack(spacing: 12) {
            // D1: the picker itself is capped at the remaining slots.
            PhotosPicker(
                selection: $pickedItems,
                maxSelectionCount: viewModel.remainingSlots,
                matching: .images
            ) {
                Image(systemName: "plus")
                    .font(.title2)
                    .frame(width: 72, height: 72)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .disabled(!viewModel.canAddMore)

            ForEach(viewModel.images) { image in
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text(image.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(width: 72, height: 72)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(alignment: .topTrailing) {
                    Button {
                        viewModel.removeImage(id: image.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: 6, y: -6)
                }
            }
        }
    }

    private var styleRow: some View {
        HStack(spacing: 12) {
            ForEach(StickerStyle.allCases) { style in
                Button {
                    viewModel.selectedStyle = style
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.thinMaterial)
                            .frame(width: 72, height: 56)
                            .overlay {
                                if viewModel.selectedStyle == style {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.tint, lineWidth: 2)
                                }
                            }
                        Text(style.displayName)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    StyleTransferSheet { _ in }
}
