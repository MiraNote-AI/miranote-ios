import MiraNoteKit
import SwiftUI

/// Sketch 2.1: text editor sheet over a blurred canvas, with the
/// voice / clean / expand / polish action row.
struct TextInputSheet: View {
    @State private var viewModel: TextInputViewModel
    @Environment(\.dismiss) private var dismiss
    let onDone: (String) -> Void

    init(services: ServiceContainer, onDone: @escaping (String) -> Void) {
        _viewModel = State(initialValue: TextInputViewModel(
            textService: services.textTransform,
            voiceService: services.voiceTranscription
        ))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $viewModel.text)
                    .scrollContentBackground(.hidden)
                    .padding()
                    .overlay(alignment: .topLeading) {
                        if viewModel.text.isEmpty {
                            Text("Text...")
                                .foregroundStyle(.tertiary)
                                .padding(24)
                                .allowsHitTesting(false)
                        }
                    }

                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 4)
                }

                actionRow
            }
            .navigationTitle("Text input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone(viewModel.text)
                        dismiss()
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.large])
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton("voice", symbol: "mic") {
                await viewModel.dictate()
            }
            ForEach(TextTransformMode.allCases) { mode in
                actionButton(mode.rawValue, symbol: symbolName(for: mode)) {
                    await viewModel.apply(mode)
                }
            }
            if viewModel.isProcessing {
                ProgressView()
                    .padding(.leading, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(viewModel.isProcessing)
    }

    private func symbolName(for mode: TextTransformMode) -> String {
        switch mode {
        case .clean: return "wand.and.stars"
        case .expand: return "text.append"
        case .polish: return "sparkles"
        }
    }
}

#Preview {
    TextInputSheet(services: .mock) { _ in }
}
