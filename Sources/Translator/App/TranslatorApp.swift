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

            Text("バージョン \(Bundle.main.translatorShortVersion) / \(Bundle.main.translatorBuildKind)")
                .foregroundStyle(.secondary)

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

private extension Bundle {
    var translatorShortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "不明"
    }

    var translatorBuildKind: String {
        #if DEBUG
        return "ローカル版"
        #else
        return bundleURL.path == "/Applications/Translator.app" ? "リリース版" : "ローカル版"
        #endif
    }
}
