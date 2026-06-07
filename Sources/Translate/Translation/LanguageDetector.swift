import Foundation

/// ローカルの文字種判定のみ（LLM を呼ばない）。
/// ひらがな・カタカナ（半角カナ含む）を含めば日本語入力 → 英訳、含まなければ和訳。
enum LanguageDetector {
    static func direction(for text: String) -> TranslationDirection {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // ひらがな 3040–309F / カタカナ 30A0–30FF / 半角カナ FF66–FF9D
            if (0x3040...0x30FF).contains(v) || (0xFF66...0xFF9D).contains(v) {
                return .toEnglish
            }
        }
        return .toJapanese
    }
}
