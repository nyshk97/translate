import SwiftUI

struct LauncherView: View {
    let model: LauncherViewModel
    @FocusState private var sourceFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // 入力行 + 方向トグル
            HStack(alignment: .top, spacing: 8) {
                TextField("翻訳したいテキスト…", text: $model.sourceText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .lineLimit(1...6)
                    .focused($sourceFocused)

                Button(action: { model.swapDirection() }) {
                    Text(model.direction.label)
                        .font(.system(size: 12, weight: .medium))
                        .monospaced()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("翻訳方向を反転")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showsOutput {
                Divider().opacity(0.4)

                Group {
                    if let err = model.errorMessage {
                        Text(err)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            Text(displayedOutput)
                                .font(.system(size: 17))
                                .foregroundStyle(model.outputText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HStack(spacing: 8) {
                    if model.isStreaming {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button(model.didCopy ? "コピー済み" : "コピー（⌘C）") {
                        model.copyResult()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(model.outputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 640, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(8)
        // 手動入力時は ⌘Return で翻訳（Return は改行に使うため）
        .background {
            Button("") { model.translate() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        }
        .onAppear { sourceFocused = true }
    }

    private var showsOutput: Bool {
        model.isStreaming || !model.outputText.isEmpty || model.errorMessage != nil
    }

    private var displayedOutput: String {
        if model.outputText.isEmpty && model.isStreaming { return "翻訳中…" }
        return model.outputText
    }
}
