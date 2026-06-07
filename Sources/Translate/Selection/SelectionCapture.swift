import AppKit
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox

/// 前面アプリの選択テキストを取得する。
/// 段階フォールバック: AXSelectedText → AXPress(Copy メニュー) → 合成 Cmd+C。
/// クリップボード経由になった場合は元の中身を復元する。
@MainActor
enum SelectionCapture {
    private struct SavedItem {
        var data: [NSPasteboard.PasteboardType: Data]
    }

    /// 現在 Accessibility 権限があるか（プロンプトは出さない）。
    static var isTrusted: Bool { AXIsProcessTrusted() }

    private enum AXResult {
        case text(String)     // 選択テキストあり
        case emptySelection   // フォーカス要素はあるが未選択
        case unsupported      // AX で取得不可
    }

    private enum CopyMenu {
        case found(AXUIElement)  // Copy 項目が見つかった（有効/無効は問わない）
        case notFound            // Copy メニューが見つからない
    }

    /// 選択テキストを取得して返す。選択が無い場合は nil。
    static func capture() async -> String? {
        guard isTrusted else {
            Log.write("SelectionCapture: accessibility 未許可")
            return nil
        }

        // 1. AX で選択テキストを直接読む（最速・副作用なし）
        switch axSelectedText() {
        case .text(let text):
            Log.write("capture: AXSelectedText 取得 (\(text.count) 文字)")
            return text
        case .emptySelection:
            Log.write("capture: AX 未選択 → 何もしない")
            return nil
        case .unsupported:
            break
        }

        // 2. Copy メニュー項目を AXPress（キーを送らないので c 漏れしない）。
        //    AXEnabled はメニュー未展開だと古い値が返るので信用せず、
        //    実際にコピーされたか（changeCount 変化）で選択有無を判定する。
        if case .found(let item) = findCopyMenuItem() {
            Log.write("capture: AXPress Copy メニュー")
            // 見つかったアプリは AXPress に賭ける。取れなければ「選択なし」とみなし、
            // キー注入（c 漏れリスク）はしない。
            return await captureViaCopyAction(settleFirst: false) { pressMenuItem(item) }
        }

        // 3. Copy メニューが無いアプリのみ、最終手段の合成 Cmd+C（flagsChanged 修正版）
        Log.write("capture: Copy メニュー無し → Cmd+C (secureInput=\(IsSecureEventInputEnabled()))")
        return await captureViaCopyAction(settleFirst: true) { await sendCommandC() }
    }

    /// Accessibility 権限を確認（未許可なら初回プロンプトを出す）。
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    // MARK: - AXSelectedText

    private static func axSelectedText() -> AXResult {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focusedElement = focused else {
            return .unsupported
        }
        let element = focusedElement as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &selected) == .success,
              let text = selected as? String else {
            return .unsupported
        }
        return text.isEmpty ? .emptySelection : .text(text)
    }

    // MARK: - Copy メニューを AXPress

    private static func findCopyMenuItem() -> CopyMenu {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .notFound }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, "AXMenuBar" as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return .notFound
        }
        return searchCopy(menuBar as! AXUIElement, depth: 0)
    }

    /// メニュー階層を辿り、cmdChar=="C" かつ修飾が ⌘ のみの項目（= Copy）を探す。
    /// タイトル固定より cmdChar で探す方がローカライズに強い。
    private static func searchCopy(_ element: AXUIElement, depth: Int) -> CopyMenu {
        guard depth <= 6 else { return .notFound }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return .notFound
        }
        for child in children {
            if let ch = axString(child, "AXMenuItemCmdChar"), ch.uppercased() == "C",
               (axInt(child, "AXMenuItemCmdModifiers") ?? -1) == 0 {
                return .found(child)
            }
            let result = searchCopy(child, depth: depth + 1)
            if case .notFound = result { continue }
            return result
        }
        return .notFound
    }

    private static func pressMenuItem(_ item: AXUIElement) {
        AXUIElementPerformAction(item, "AXPress" as CFString)
    }

    private static func axString(_ e: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
    private static func axInt(_ e: AXUIElement, _ attr: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return nil }
        return ref as? Int
    }
    private static func axBool(_ e: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success else { return nil }
        return ref as? Bool
    }

    // MARK: - クリップボード経由（Copy 実行 → 読み取り → 復元）

    private static func captureViaCopyAction(settleFirst: Bool, _ trigger: () async -> Void) async -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let savedString = saved.first?.data[.string].flatMap { String(data: $0, encoding: .utf8) }
        let preCount = pb.changeCount

        if settleFirst {
            // ⌘H の解放が OS に伝わって修飾状態が落ち着くのを待つ
            try? await Task.sleep(for: .milliseconds(30))
        }
        await trigger()

        var copied: String?
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(10))
            if pb.changeCount != preCount {
                try? await Task.sleep(for: .milliseconds(20))
                copied = pb.string(forType: .string)
                break
            }
        }

        restore(pb, saved)

        // 遅延クロバー対策（Electron 系が数百ms 後に再書き込みするため）
        if let copied, !copied.isEmpty {
            scheduleAntiClobber(pb, saved: saved, savedString: savedString)
        }

        if let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return copied
        }
        return nil
    }

    /// 合成 Cmd+C。修飾キーは flagsChanged で送る（keyDown/keyUp だと実効 modifier にならず
    /// 素の「c」が漏れる）。さらに局所イベント抑制で物理キーの割り込みを防ぐ。
    private static func sendCommandC() async {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.localEventsSuppressionInterval = 0.15
        source.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)

        let keyCmd = CGKeyCode(kVK_Command)
        let keyC = CGKeyCode(kVK_ANSI_C)
        let tap: CGEventTapLocation = .cghidEventTap

        func postModifier(down: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCmd, keyDown: down) else { return }
            e.type = .flagsChanged
            e.flags = down ? .maskCommand : []
            e.post(tap: tap)
        }
        func postC(down: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: down) else { return }
            e.flags = .maskCommand
            e.post(tap: tap)
        }

        postModifier(down: true)
        try? await Task.sleep(for: .milliseconds(20))
        postC(down: true)
        try? await Task.sleep(for: .milliseconds(10))
        postC(down: false)
        try? await Task.sleep(for: .milliseconds(20))
        postModifier(down: false)
    }

    // MARK: - クリップボード退避・復元

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

    private static func snapshot(_ pb: NSPasteboard) -> [SavedItem] {
        pb.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = Data(data)
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
