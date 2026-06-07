import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock に出さないメニューバー常駐アプリ
        NSApp.setActivationPolicy(.accessory)
        Log.write("applicationDidFinishLaunching")

        // 起動時ウォームアップ（TLS/HTTP2 を温める）
        LauncherController.shared.model.warmUp()

        // Accessibility 権限の確認（未許可なら初回プロンプト。以降 capture() は非プロンプトで判定）
        SelectionCapture.ensureAccessibility()

        // グローバルショートカット登録。
        // 翻訳は onKeyUp（⌘H を離した後）に発火させる。onKeyDown だと物理 Cmd を
        // 握ったまま合成 Cmd+C を注入することになり、修飾が外れて「c」が素通りするため。
        KeyboardShortcuts.onKeyUp(for: .translate) {
            Task { await AppDelegate.onTranslateHotkey() }
        }
        KeyboardShortcuts.onKeyUp(for: .screenshotTranslate) {
            Task { await AppDelegate.onScreenshotHotkey() }
        }
    }

    /// ⌘⇧H: 範囲選択スクショ → Gemini で翻訳。
    @MainActor
    private static func onScreenshotHotkey() async {
        // パネルは開かず、まず範囲選択させる（キャンセルなら何もしない）
        guard let data = await ScreenshotCapture.captureInteractive() else { return }
        LauncherController.shared.presentImage(data, mimeType: "image/png")
    }

    /// ⌘H: 開いていれば閉じる。閉じていれば前面アプリの選択を取得して翻訳。
    @MainActor
    private static func onTranslateHotkey() async {
        if LauncherController.shared.isVisible {
            LauncherController.shared.hide()
            return
        }
        // 自アプリを活性化する前に、前面アプリから選択テキストを取得
        let selected = await SelectionCapture.capture()
        LauncherController.shared.present(prefill: selected)
    }
}
