import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// テキスト翻訳（既定: ⌘H）。選択があれば即翻訳、無ければ空ランチャー。
    /// Name は実質イミュータブルな値型のため nonisolated(unsafe) で Sendable チェックをオプトアウト。
    nonisolated(unsafe) static let translate = Self("translate", default: .init(.h, modifiers: [.command]))

    /// スクショ翻訳（既定: ⌘⇧H）。
    nonisolated(unsafe) static let screenshotTranslate = Self("screenshotTranslate", default: .init(.h, modifiers: [.command, .shift]))
}
