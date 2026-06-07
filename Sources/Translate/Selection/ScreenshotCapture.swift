import AppKit

/// 範囲選択スクリーンショット（OS 標準 `screencapture -i`）。
enum ScreenshotCapture {
    /// 十字カーソルで範囲選択させ、PNG データを返す。キャンセル時は nil。
    static func captureInteractive() async -> Data? {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("translate-shot-\(UUID().uuidString).png")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                proc.arguments = ["-i", "-x", tmp.path] // -i 対話選択 / -x 音を鳴らさない
                do {
                    try proc.run()
                    proc.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = try? Data(contentsOf: tmp)
                try? FileManager.default.removeItem(at: tmp)
                continuation.resume(returning: data) // キャンセル時はファイル未作成 → nil
            }
        }
    }
}
