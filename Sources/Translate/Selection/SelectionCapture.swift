import AppKit
import CoreGraphics
import ApplicationServices

/// 前面アプリの選択テキストを合成 Cmd+C で取得する。元のクリップボードは復元する。
@MainActor
enum SelectionCapture {
    /// 退避した1アイテム分の中身（type→bytes を即時コピーして保持）。
    private struct SavedItem {
        var data: [NSPasteboard.PasteboardType: Data]
    }

    /// 現在 Accessibility 権限があるか（プロンプトは出さない）。
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 選択テキストを取得して返す。選択が無い（クリップボードが変化しない）場合は nil。
    static func capture() async -> String? {
        guard isTrusted else {
            Log.write("SelectionCapture: accessibility 未許可")
            return nil
        }

        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let savedString = saved.first?.data[.string].flatMap { String(data: $0, encoding: .utf8) }
        let preCount = pb.changeCount

        sendCommandC()

        var copied: String?
        // コピー反映を最大 ~500ms ポーリング（changeCount の変化で検知）
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(10))
            if pb.changeCount != preCount {
                // 変化検知後、書き込み完了を待つため一拍置いてから読む
                try? await Task.sleep(for: .milliseconds(20))
                copied = pb.string(forType: .string)
                break
            }
        }

        restore(pb, saved)

        // 遅延クロバー対策: コピー元アプリ（Electron 系等）が数百ms 後に選択テキストを
        // 再書き込みしてくることがある。⌘H 後しばらくは元のクリップボードを保つ。
        if let copied, !copied.isEmpty {
            scheduleAntiClobber(pb, saved: saved, savedString: savedString)
        }

        if let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return copied
        }
        return nil
    }

    /// 復元後しばらく監視し、元と違う値に上書きされたら元に戻す（最大 ~1.2s）。
    private static func scheduleAntiClobber(
        _ pb: NSPasteboard, saved: [SavedItem], savedString: String?
    ) {
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(40))
                if pb.string(forType: .string) != savedString {
                    restore(pb, saved)
                }
            }
        }
    }

    /// Accessibility 権限を確認（未許可なら初回プロンプトを出す）。
    @discardableResult
    static func ensureAccessibility() -> Bool {
        // kAXTrustedCheckOptionPrompt の値（C グローバル var は Swift 6 で concurrency-unsafe のため文字列リテラルを使用）
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 0x08 // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// 全アイテム・全タイプのバイト列を即時コピーして退避（遅延評価を避ける）。
    private static func snapshot(_ pb: NSPasteboard) -> [SavedItem] {
        pb.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = Data(data) // 明示コピー
                }
            }
            return SavedItem(data: dict)
        } ?? []
    }

    private static func restore(_ pb: NSPasteboard, _ saved: [SavedItem]) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in saved.data {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(items)
    }
}
