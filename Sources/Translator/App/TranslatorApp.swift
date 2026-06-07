import SwiftUI

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバー常駐アイコン（クリックでメニュー）
        MenuBarExtra("Translator", systemImage: "character.bubble.fill") {
            Button("翻訳パネルを開く") {
                LauncherController.shared.toggle()
            }
            .keyboardShortcut("h")

            SettingsLink {
                Text("設定…")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Translator を終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        // 設定ウィンドウ（⌘, またはメニューから開く）
        Settings {
            SettingsView()
        }
    }
}
