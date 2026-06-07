import Foundation
import AppKit

/// ランチャーの状態と翻訳実行を司る。
@MainActor
@Observable
final class LauncherViewModel {
    var sourceText = ""
    var outputText = ""
    var direction: TranslationDirection = .toEnglish
    var isStreaming = false
    var errorMessage: String?
    var didCopy = false

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private let service = TranslationService()

    func warmUp() {
        service.warmUp()
    }

    /// パネル表示時の初期化。prefill があれば即翻訳、無ければ空入力。
    func configure(prefill: String?) {
        streamTask?.cancel()
        outputText = ""
        errorMessage = nil
        didCopy = false
        isStreaming = false
        if let prefill, !prefill.isEmpty {
            sourceText = prefill
            direction = LanguageDetector.direction(for: prefill)
            translate()
        } else {
            sourceText = ""
        }
    }

    func translate() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        streamTask?.cancel()
        outputText = ""
        errorMessage = nil
        didCopy = false
        isStreaming = true
        let dir = direction
        let service = self.service
        streamTask = Task { [weak self] in
            var buffer = ""
            var lastFlush = ContinuousClock.now
            do {
                for try await delta in service.stream(text: text, direction: dir) {
                    buffer += delta
                    // 30〜50ms バッファしてから state 更新（トークン毎再描画のカクつき回避）
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(40) {
                        self?.outputText += buffer
                        buffer = ""
                        lastFlush = now
                    }
                }
                if !buffer.isEmpty { self?.outputText += buffer }
            } catch is CancellationError {
                // 中断は無視
            } catch {
                self?.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self?.isStreaming = false
        }
    }

    func swapDirection() {
        direction = direction.toggled
        translate()
    }

    func copyResult() {
        guard !outputText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(outputText, forType: .string)
        didCopy = true
    }

    func cancel() {
        streamTask?.cancel()
        isStreaming = false
    }
}
