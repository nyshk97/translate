import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("一般", systemImage: "gearshape") }
            KeysSettingsView()
                .tabItem { Label("APIキー", systemImage: "key") }
            ShortcutsSettingsView()
                .tabItem { Label("ショートカット", systemImage: "command") }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettingsView: View {
    // Phase 5 で SMAppService と連動させる
    @State private var launchAtLogin = true

    var body: some View {
        Form {
            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .disabled(true)
            Text("※ ログイン項目連携は Phase 5 で実装します")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct KeysSettingsView: View {
    @State private var groqKey = ""
    @State private var geminiKey = ""

    var body: some View {
        Form {
            Section("Groq（テキスト翻訳）") {
                SecureField("gsk_…", text: $groqKey)
                Button("保存") { KeychainStore.set(groqKey, for: .groq) }
                    .disabled(groqKey.isEmpty)
            }
            Section("Gemini（スクショ・画像）") {
                SecureField("AIza…", text: $geminiKey)
                Button("保存") { KeychainStore.set(geminiKey, for: .gemini) }
                    .disabled(geminiKey.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            groqKey = KeychainStore.get(.groq) ?? ""
            geminiKey = KeychainStore.get(.gemini) ?? ""
        }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("翻訳:", name: .translate)
            KeyboardShortcuts.Recorder("スクショ翻訳:", name: .screenshotTranslate)
        }
        .formStyle(.grouped)
        .padding()
    }
}
