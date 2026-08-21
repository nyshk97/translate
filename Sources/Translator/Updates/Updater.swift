import AppKit
import Combine
#if !DEBUG
import Sparkle
#endif

/// Sparkle によるアプリ内アップデート。
///
/// - Debug（ローカル版）は何もしない。Info.plist にも feed が入っていない（project.yml の
///   TRANSLATOR_SU_FEED_URL は Release 構成だけ）。ローカル版が常用版のダウンロードで
///   置き換わる事故を、コードと plist の二重で防ぐ。
/// - 自動チェックは Info.plist の SUEnableAutomaticChecks で ON（起動時 + 24h ごと）。
///   常駐して存在を忘れるアプリなので、手動だけだと更新が永久に取りこぼされる。
/// - gentle reminder の delegate は渡さない（LSUIElement アプリはほぼ常に非アクティブで、
///   半端に実装すると自動チェックが更新を見つけても無言で終わる）。Sparkle 標準のアラートに任せる。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// dev 版ではメニュー項目を無効化する。
    static let isSupported: Bool = {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }()

    @Published private(set) var canCheckForUpdates = false

    #if !DEBUG
    private let controller: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()
    #endif

    private init() {
        #if !DEBUG
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
        #endif
    }

    /// メニューの「アップデートを確認…」。Sparkle の進捗と結果ダイアログが出る。
    func checkForUpdates() {
        #if !DEBUG
        // accessory アプリなので前面化しないと Sparkle のダイアログが背面に出る
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }
}
