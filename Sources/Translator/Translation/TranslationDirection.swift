import Foundation

/// 翻訳方向。判定は「日本語か否か」の2値だけ（CLAUDE.md の方針）。
enum TranslationDirection: Sendable {
    case toEnglish   // 日本語 → 英語
    case toJapanese  // それ以外 → 日本語

    /// 短い固定プロンプト（入力トークン最小化で TTFT を縮める）。
    var systemPrompt: String {
        switch self {
        case .toEnglish:
            return "Translate Japanese into natural, idiomatic English. Preserve the meaning, tone, names, numbers, URLs, and formatting. Do not translate word-for-word; rewrite awkward literal phrasing. Output only the translation."
        case .toJapanese:
            return "Translate the text into natural, idiomatic Japanese. Preserve the meaning, tone, names, numbers, URLs, and formatting. Do not translate word-for-word; rewrite awkward literal phrasing. Use Japanese that reads as if originally written in Japanese. Prefer common Japanese phrasing over stiff dictionary wording, e.g. translate \"too literal\" as \"直訳っぽい\" when natural. Output only the translation."
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

    /// 永続化用の安定キー。
    var key: String {
        self == .toEnglish ? "toEnglish" : "toJapanese"
    }

    static func from(key: String) -> TranslationDirection {
        key == "toJapanese" ? .toJapanese : .toEnglish
    }
}
