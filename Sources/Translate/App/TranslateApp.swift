import SwiftUI

@main
struct TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバー常駐アイコン（クリックでメニュー）
        MenuBarExtra("Translate", systemImage: "character.bubble.fill") {
            Button("翻訳パネルを開く") {
                LauncherController.shared.toggle()
            }
            .keyboardShortcut("o")

            SettingsLink {
                Text("設定…")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Translate を終了") {
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
