import SwiftUI

struct LauncherView: View {
    let model: LauncherViewModel
    @FocusState private var sourceFocused: Bool
    @State private var showNuance = false

    private let nuancePresets: [(label: String, instruction: String)] = [
        ("丁寧に", "Use a more polite, formal tone."),
        ("カジュアルに", "Use a more casual, friendly tone."),
        ("短く", "Make it more concise."),
        ("直訳", "Translate more literally, staying close to the source."),
    ]

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            inputRow(model: model)

            if showsOutput {
                Divider().opacity(0.4)
                outputArea
                if !model.isStreaming && !model.outputText.isEmpty {
                    actionRow(model: model)
                }
                if showNuance {
                    nuanceControls(model: model)
                }
                if showsBack {
                    auxSection(title: "戻し訳", text: model.backTranslation, loading: model.isBackTranslating)
                }
                if showsTones {
                    tonesSection
                }
            } else if !model.historyResults.isEmpty {
                historyList(model: model)
            }
        }
        .frame(width: 640, alignment: .leading)
        .onChange(of: model.sourceText) { _, _ in model.refreshHistory() }
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

    // MARK: - 入力

    @ViewBuilder
    private func inputRow(model: LauncherViewModel) -> some View {
        if model.isVision, let image = model.image {
            // 画像翻訳モード: サムネイル＋ラベル
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 140, maxHeight: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1)))
                Text("画像を翻訳")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            HStack(alignment: .top, spacing: 8) {
                TextField("翻訳したいテキスト…", text: Binding(get: { model.sourceText }, set: { model.sourceText = $0 }), axis: .vertical)
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
        }
    }

    // MARK: - 履歴（空状態）

    private func historyList(model: LauncherViewModel) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.historyResults) { entry in
                        HistoryRow(entry: entry) { model.loadEntry(entry) }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - 主出力

    private var outputArea: some View {
        Group {
            if let err = model.errorMessage {
                Text(err)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    Text(model.outputText.isEmpty && model.isStreaming ? "翻訳中…" : model.outputText)
                        .font(.system(size: 17))
                        .foregroundStyle(model.outputText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - アクション行

    private func actionRow(model: LauncherViewModel) -> some View {
        HStack(spacing: 6) {
            // 戻し訳・トーン・調整はテキスト経路のみ（画像翻訳では出さない）
            if !model.isVision {
                actionButton("戻し訳", systemImage: "arrow.uturn.left") { model.backTranslate() }
                actionButton("トーン", systemImage: "slider.horizontal.3") { model.generateTones() }
                actionButton("調整", systemImage: "wand.and.stars", active: showNuance) { showNuance.toggle() }
            }
            Spacer()
            Button(model.didCopy ? "コピー済み" : "コピー（⌘C）") { model.copyResult() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.outputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func actionButton(_ title: String, systemImage: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? .white.opacity(0.16) : .white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ニュアンス調整

    private func nuanceControls(model: LauncherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(nuancePresets, id: \.label) { preset in
                    Button(preset.label) { model.applyNuance(preset.instruction) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            TextField("指示を入力（例: もっと簡潔に）", text: Binding(get: { model.nuanceInstruction }, set: { model.nuanceInstruction = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { model.applyNuance(model.nuanceInstruction) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 戻し訳 / トーン

    private func auxSection(title: String, text: String, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().opacity(0.3)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(text.isEmpty && loading ? "…" : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var tonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.3)
            toneCard("フォーマル", text: model.toneFormal, loading: model.isGeneratingTones && model.toneFormal.isEmpty)
            toneCard("カジュアル", text: model.toneCasual, loading: model.isGeneratingTones && model.toneCasual.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func toneCard(_ title: String, text: String, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty && loading ? "…" : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 可視判定

    private var showsOutput: Bool {
        model.isStreaming || !model.outputText.isEmpty || model.errorMessage != nil
    }
    private var showsBack: Bool {
        model.isBackTranslating || !model.backTranslation.isEmpty
    }
    private var showsTones: Bool {
        model.isGeneratingTones || !model.toneFormal.isEmpty || !model.toneCasual.isEmpty
    }
}

/// 履歴一覧の1行（ホバーで強調、クリックで呼び戻し）。
private struct HistoryRow: View {
    let entry: HistoryEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(entry.directionValue.label)
                    .font(.system(size: 9, weight: .medium))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.source)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(entry.output)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.white.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
