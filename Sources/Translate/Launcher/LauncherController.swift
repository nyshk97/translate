import AppKit
import SwiftUI

/// ランチャーパネルの生成・表示・配置を管理するシングルトン。
@MainActor
final class LauncherController {
    static let shared = LauncherController()

    let model = LauncherViewModel()
    private var panel: LauncherPanel?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 選択テキスト（prefill）があれば即翻訳しつつパネルを開く。
    func present(prefill: String?) {
        model.configure(prefill: prefill)
        showPanel()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            present(prefill: nil)
        }
    }

    /// 画像（スクショ / ペースト / ドロップ）を翻訳しつつパネルを開く。
    func presentImage(_ data: Data, mimeType: String) {
        model.translateImage(data, mimeType: mimeType)
        showPanel()
    }

    func hide() {
        panel?.orderOut(nil)
        model.cancel()
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // 開くたびにフレッシュな hosting controller を載せ、onAppear でフォーカスを当てる。
        // .preferredContentSize でストリーミング中もパネル高さが内容に追従する。
        let hosting = NSHostingController(rootView: LauncherView(model: model))
        hosting.sizingOptions = .preferredContentSize
        panel.contentViewController = hosting
        panel.layoutIfNeeded()

        position(panel)
        model.warmUp()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel()
        panel.onClose = { [weak self] in self?.hide() }
        return panel
    }

    /// マウスのある画面の中央・上寄りに、パネル上端を固定して配置。
    private func position(_ panel: LauncherPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let topY = visible.maxY - visible.height * 0.18
        let x = visible.midX - size.width / 2
        panel.setFrameOrigin(NSPoint(x: x, y: topY - size.height))
    }
}
