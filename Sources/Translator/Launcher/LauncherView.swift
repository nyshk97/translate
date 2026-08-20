import SwiftUI

/// Obsidian テーマ: 不透明ダーク・高コントラスト・入力は薄く出力は強く。
enum Theme {
    static let panel = Color(red: 0x15/255, green: 0x16/255, blue: 0x1b/255)
    static let header = Color(red: 0x1b/255, green: 0x1c/255, blue: 0x22/255)
    static let chip = Color(red: 0x2a/255, green: 0x2b/255, blue: 0x33/255)
    static let button = Color(red: 0x22/255, green: 0x23/255, blue: 0x2b/255)
    static let buttonBorder = Color(red: 0x2d/255, green: 0x2e/255, blue: 0x38/255)
    static let text = Color(red: 0xf2/255, green: 0xf2/255, blue: 0xf5/255)
    static let muted = Color(red: 0x9a/255, green: 0x9c/255, blue: 0xa8/255)
    static let chipText = Color(red: 0xc9/255, green: 0xca/255, blue: 0xd4/255)
    static let buttonText = Color(red: 0xd5/255, green: 0xd6/255, blue: 0xdf/255)
    static let accent = Color(red: 0x7c/255, green: 0xc4/255, blue: 0xff/255)
    static let radius: CGFloat = 18
}

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
                StreamingBar(active: model.isStreaming)
                // 入力欄は固定、以降は1つの ScrollView にまとめて高さ上限を付ける
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                    }
                }
                .frame(maxHeight: 460)
            } else if !model.historyResults.isEmpty {
                historyList(model: model)
            }
        }
        .frame(width: 640, alignment: .leading)
        .onChange(of: model.sourceText) { _, _ in model.refreshHistory() }
        .foregroundStyle(Theme.text)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .colorScheme(.dark)
        .padding(8)
        // Enter で翻訳（ペーストした改行は保持されるが、手動の Return キーは翻訳に割り当て）
        .background {
            Button("") { model.translate() }
                .keyboardShortcut(.return, modifiers: [])
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
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.header)
        } else {
            HStack(alignment: .top, spacing: 8) {
                TextField("翻訳したいテキスト…", text: Binding(get: { model.sourceText }, set: { model.sourceText = $0 }), axis: .vertical)
                    .textFieldStyle(.plain)
                    // 出力が出ている間は「入力は控えめ・出力が主役」に切り替える
                    .font(.system(size: showsOutput ? 12.5 : 16))
                    .foregroundStyle(showsOutput ? Theme.muted : Theme.text)
                    .lineSpacing(3)
                    .lineLimit(1...6)
                    .focused($sourceFocused)

                Button(action: { model.swapDirection() }) {
                    Text(model.direction.label)
                        .font(.system(size: 11, weight: .medium))
                        .monospaced()
                        .foregroundStyle(Theme.chipText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("翻訳方向を反転")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(showsOutput ? Theme.header : Theme.panel)
        }
    }

    // MARK: - 履歴（空状態）

    private func historyList(model: LauncherViewModel) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
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
                // ストリーミング中は末尾にアクセント色のカーソルをインラインで付ける（行末に追従させるため Text 連結）
                (Text(model.outputText) + Text(model.isStreaming ? "▍" : "").foregroundColor(Theme.accent))
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
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
            Button(action: { model.copyResult() }) {
                HStack(spacing: 5) {
                    Text(model.didCopy ? "コピー済み" : "コピー")
                        .font(.system(size: 12, weight: .medium))
                    Text("⌘C")
                        .font(.system(size: 10, design: .monospaced))
                        .opacity(0.6)
                }
                .foregroundStyle(model.didCopy ? Theme.muted : Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: .command)
            .disabled(model.outputText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func actionButton(_ title: String, systemImage: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Theme.text : Theme.buttonText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Theme.chip : Theme.button, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.buttonBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ニュアンス調整

    private func nuanceControls(model: LauncherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(nuancePresets, id: \.label) { preset in
                    Button(action: { model.applyNuance(preset.instruction) }) {
                        Text(preset.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.buttonText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.buttonBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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

    // MARK: - 戻し訳 / トーン（薄いカードで主出力と区別）

    private func auxSection(title: String, text: String, loading: Bool) -> some View {
        card {
            labeledBlock(title, text: text, loading: loading)
        }
    }

    private var tonesSection: some View {
        card {
            labeledBlock("フォーマル", text: model.toneFormal, loading: model.isGeneratingTones && model.toneFormal.isEmpty)
            Divider().opacity(0.25)
            labeledBlock("カジュアル", text: model.toneCasual, loading: model.isGeneratingTones && model.toneCasual.isEmpty)
        }
    }

    /// キャプション＋本文の1ブロック。
    private func labeledBlock(_ title: String, text: String, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.muted)
            Text(text.isEmpty && loading ? "…" : text)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(text.isEmpty ? Theme.muted : Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 薄い背景のカード。主出力と視覚的に区別する。
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.header, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.buttonBorder, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.output)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(entry.source)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.header : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 入力と出力の境界線。ストリーミング中は光が流れる。
private struct StreamingBar: View {
    let active: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.06))
            if active {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Theme.accent, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                        .onAppear {
                            phase = -0.6
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                }
            }
        }
        .frame(height: 2)
        .clipped()
    }
}
