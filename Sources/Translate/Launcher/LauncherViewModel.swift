import Foundation
import AppKit

/// ランチャーの状態と翻訳実行を司る。
@MainActor
@Observable
final class LauncherViewModel {
    // 入力・主翻訳
    var sourceText = ""
    var outputText = ""
    var direction: TranslationDirection = .toEnglish
    var isStreaming = false
    var errorMessage: String?
    var didCopy = false

    // 戻し訳
    var backTranslation = ""
    var isBackTranslating = false

    // トーン2案
    var toneFormal = ""
    var toneCasual = ""
    var isGeneratingTones = false

    // ニュアンス自由入力欄
    var nuanceInstruction = ""

    // 履歴（空状態で一覧＋インクリメンタル検索）
    var historyResults: [HistoryEntry] = []

    // 画像翻訳（vision）
    var image: NSImage?
    var isVision = false

    @ObservationIgnored private var mainTask: Task<Void, Never>?
    @ObservationIgnored private var backTask: Task<Void, Never>?
    @ObservationIgnored private var tonesTask: Task<Void, Never>?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private let service = TranslationService()
    @ObservationIgnored private let gemini = GeminiService()

    func warmUp() {
        service.warmUp()
        gemini.warmUp()
    }

    /// パネル表示時の初期化。prefill があれば即翻訳、無ければ空入力。
    func configure(prefill: String?) {
        cancelAll()
        clearOutputs()
        errorMessage = nil
        didCopy = false
        nuanceInstruction = ""
        image = nil
        isVision = false
        if let prefill, !prefill.isEmpty {
            sourceText = prefill
            translate() // redetect=true で sourceText から方向判定
        } else {
            sourceText = ""
            isStreaming = false
        }
        refreshHistory()
    }

    /// 現在の入力に応じて履歴を更新（空なら最近、入力ありなら検索）。120ms デバウンス。
    func refreshHistory() {
        historyTask?.cancel()
        let query = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        historyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let results = query.isEmpty
                ? await HistoryStore.shared.recent(limit: 30)
                : await HistoryStore.shared.search(query, limit: 30)
            if Task.isCancelled { return }
            self?.historyResults = results
        }
    }

    /// 履歴エントリを呼び戻す（API を呼ばず保存済みの訳を表示）。
    func loadEntry(_ entry: HistoryEntry) {
        cancelAll()
        clearOutputs()
        errorMessage = nil
        didCopy = false
        sourceText = entry.source
        direction = entry.directionValue
        outputText = entry.output
        image = nil
        isVision = false
        isStreaming = false
    }

    /// 主翻訳。instruction を渡すとニュアンス調整付きで再翻訳。
    /// redetect=true のとき入力テキストから翻訳方向を判定する（手動入力時）。
    /// 手動トグル・ニュアンス調整では false にして現在の方向を維持する。
    func translate(instruction: String? = nil, redetect: Bool = true) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if redetect {
            direction = LanguageDetector.direction(for: text)
        }
        cancelAll()
        clearOutputs()
        errorMessage = nil
        didCopy = false
        image = nil
        isVision = false
        isStreaming = true
        let dir = direction
        mainTask = Task { [weak self] in
            await self?.runStream(text: text, direction: dir, instruction: instruction) { chunk in
                self?.outputText += chunk
            }
            if Task.isCancelled { return } // キャンセル後は副作用を走らせない
            self?.isStreaming = false
            self?.recordHistory(source: text, direction: dir)
        }
    }

    /// 画像翻訳（vision）。スクショ / ペースト / ドロップ共通の入口。
    func translateImage(_ data: Data, mimeType: String) {
        cancelAll()
        clearOutputs()
        errorMessage = nil
        didCopy = false
        nuanceInstruction = ""
        sourceText = ""
        image = NSImage(data: data)
        isVision = true
        isStreaming = true
        let gemini = self.gemini
        mainTask = Task { [weak self] in
            await self?.runVisionStream(data: data, mimeType: mimeType, gemini: gemini)
            if Task.isCancelled { return }
            self?.isStreaming = false
            self?.recordVisionHistory()
        }
    }

    /// vision ストリームを 40ms バッファしながら outputText に流す。
    private func runVisionStream(data: Data, mimeType: String, gemini: GeminiService) async {
        var buffer = ""
        var lastFlush = ContinuousClock.now
        do {
            for try await delta in gemini.streamImageTranslation(imageData: data, mimeType: mimeType) {
                buffer += delta
                let now = ContinuousClock.now
                if now - lastFlush >= .milliseconds(40) {
                    outputText += buffer
                    buffer = ""
                    lastFlush = now
                }
            }
            if !buffer.isEmpty { outputText += buffer }
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recordVisionHistory() {
        guard errorMessage == nil, !outputText.isEmpty else { return }
        let output = outputText
        let now = Date().timeIntervalSince1970
        Task.detached {
            await HistoryStore.shared.insert(
                source: "🖼 画像", output: output, direction: "toJapanese",
                model: GeminiService.modelName, createdAt: now
            )
        }
    }

    /// 主翻訳が成功したらバックグラウンドで履歴に追記（初動を阻害しない）。
    private func recordHistory(source: String, direction: TranslationDirection) {
        guard errorMessage == nil, !outputText.isEmpty else { return }
        let output = outputText
        let key = direction.key
        let now = Date().timeIntervalSince1970
        Task.detached {
            await HistoryStore.shared.insert(
                source: source, output: output, direction: key,
                model: TranslationService.modelName, createdAt: now
            )
        }
    }

    func swapDirection() {
        direction = direction.toggled
        translate(redetect: false) // 手動指定なので再判定しない
    }

    /// 戻し訳: 出力を逆方向にもう一度翻訳して意味を確認する。
    func backTranslate() {
        guard !outputText.isEmpty else { return }
        backTask?.cancel()
        backTranslation = ""
        isBackTranslating = true
        let text = outputText
        let dir = direction.toggled
        backTask = Task { [weak self] in
            await self?.runStream(text: text, direction: dir, instruction: nil) { chunk in
                self?.backTranslation += chunk
            }
            if Task.isCancelled { return }
            self?.isBackTranslating = false
        }
    }

    /// トーン2案: フォーマル / カジュアルを順にストリーム生成する。
    func generateTones() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tonesTask?.cancel()
        toneFormal = ""
        toneCasual = ""
        isGeneratingTones = true
        let dir = direction
        tonesTask = Task { [weak self] in
            await self?.runStream(text: text, direction: dir, instruction: "Use a formal, polite tone.") { chunk in
                self?.toneFormal += chunk
            }
            if Task.isCancelled { return }
            await self?.runStream(text: text, direction: dir, instruction: "Use a casual, friendly, conversational tone.") { chunk in
                self?.toneCasual += chunk
            }
            if Task.isCancelled { return }
            self?.isGeneratingTones = false
        }
    }

    /// ニュアンス調整: 指示付きで主翻訳をやり直す（方向は維持）。
    func applyNuance(_ instruction: String) {
        translate(instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines), redetect: false)
    }

    func copyResult() {
        guard !outputText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(outputText, forType: .string)
        didCopy = true
    }

    func cancel() {
        cancelAll()
        isStreaming = false
        isBackTranslating = false
        isGeneratingTones = false
    }

    // MARK: - private

    /// ストリームを 40ms バッファしながら onDelta に流す共通処理。
    private func runStream(
        text: String, direction: TranslationDirection, instruction: String?,
        onDelta: @escaping (String) -> Void
    ) async {
        var buffer = ""
        var lastFlush = ContinuousClock.now
        do {
            for try await delta in service.stream(text: text, direction: direction, instruction: instruction) {
                buffer += delta
                let now = ContinuousClock.now
                if now - lastFlush >= .milliseconds(40) {
                    onDelta(buffer)
                    buffer = ""
                    lastFlush = now
                }
            }
            if !buffer.isEmpty { onDelta(buffer) }
        } catch is CancellationError {
            // 中断は無視
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearOutputs() {
        outputText = ""
        backTranslation = ""
        toneFormal = ""
        toneCasual = ""
    }

    private func cancelAll() {
        mainTask?.cancel()
        backTask?.cancel()
        tonesTask?.cancel()
        historyTask?.cancel()
    }
}
