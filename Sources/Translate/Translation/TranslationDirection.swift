import Foundation

/// 翻訳方向。判定は「日本語か否か」の2値だけ（CLAUDE.md の方針）。
enum TranslationDirection: Sendable {
    case toEnglish   // 日本語 → 英語
    case toJapanese  // それ以外 → 日本語

    /// 短い固定プロンプト（入力トークン最小化で TTFT を縮める）。
    var systemPrompt: String {
        switch self {
        case .toEnglish:
            return "Translate the Japanese text into natural English. Output only the translation, with no notes or explanations."
        case .toJapanese:
            return "Translate the text into natural Japanese. Output only the translation, with no notes or explanations."
        }
    }

    var label: String {
        switch self {
        case .toEnglish: return "あ → A"
        case .toJapanese: return "A → あ"
        }
    }

    var toggled: TranslationDirection {
        self == .toEnglish ? .toJapanese : .toEnglish
    }
}
