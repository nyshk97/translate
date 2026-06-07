import AppKit

/// Spotlight 風のフローティングパネル。Esc / 外クリックで閉じる。
final class LauncherPanel: NSPanel {
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 96),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        // .canJoinAllSpaces と .moveToActiveSpace は排他（同時指定すると例外）。
        // 全スペース表示＋フルスクリーン上表示はこの2つで足りる。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 内容サイズが変わっても上端を固定する（ストリーミングで下方向に伸びる）。
    override func setContentSize(_ size: NSSize) {
        guard isVisible else {
            super.setContentSize(size)
            return
        }
        let oldTop = frame.maxY
        super.setContentSize(size)
        var origin = frame.origin
        origin.y = oldTop - frame.height
        setFrameOrigin(origin)
    }

    /// 外クリックでフォーカスを失ったら閉じる
    override func resignKey() {
        super.resignKey()
        onClose?()
    }

    /// Esc で閉じる
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}
