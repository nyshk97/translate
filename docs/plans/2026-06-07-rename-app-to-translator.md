# アプリ表示名を Translator に変更（🟢 変えやすい範囲のみ）

## 概要・やりたいこと

アプリ名を `Translate` → `Translator` に変更する。ただし今回は **AI で完結できる「変えやすい」範囲のみ** を対象にする。

- 目的: 表示名・コード/ビルド構成・ドキュメント上の `Translate` を `Translator` に統一する。
- 方針: 既存の権限（TCC）・APIキー（Keychain）・翻訳履歴・配布チャネル（GitHub / Homebrew）を**一切壊さない**範囲に限定する。これらに触れる変更（Bundle ID / Keychain サービス名 / 履歴パス / ローカルディレクトリ名 / GitHub リポジトリ名 / cask token）は今回スコープ外。

## 前提・わかっていること

- このアプリは**自分専用**（ユーザーは本人だけ）。他人のデータ移行は不要。
- 影響箇所は調査済み。今回触るのは「単純な文字列置換・ファイル rename で閉じ、実害なく、ビルドで検証できる」もののみ。
- **据え置く（今回触らない）もの** ＝ これらが無傷なので権限再付与・APIキー再入力・履歴移行が不要:
  - Bundle ID: `com.d0ne1s.translate`（`project.yml:37` の `PRODUCT_BUNDLE_IDENTIFIER`）
  - Keychain サービス名: `com.d0ne1s.translate`（`KeychainStore.swift:7`）
  - 履歴DB保存先: `~/Library/Application Support/com.d0ne1s.translate`（`HistoryStore.swift:49`）
  - ローカルディレクトリ `/Users/d0ne1s/translate`、GitHub リポジトリ `nyshk97/translate`、cask token `translate-mac`
- 整合性メモ:
  - `project.yml` の target 名を変えると `PRODUCT_NAME` 連動で `.app` 名・プロセス名（`killall`/`pgrep` 対象）・`.xcodeproj` 名がすべて `Translator` になる → mise タスク・スクリプト・VERIFY.md を追従させる。
  - `PRODUCT_BUNDLE_IDENTIFIER` は `project.yml` で明示設定されているため、target 名を変えても Bundle ID は据え置きのまま（自動で変わらない）。
  - `Sources/Translate/` サブディレクトリ名は `project.yml` の `sources: path: Sources` には影響しない（`Sources` を指しているだけ）ので rename しても設定変更は不要。
  - コード上の `Translation` / `TranslationService` / `backTranslate` / `onTranslateHotkey` / `.translate`（ショートカット名）等は「翻訳という機能名」でありアプリ名ではないので**変更しない**。
  - 過去の plan ファイル（`docs/plans/2026-06-07-macos-translator.md` 等）は歴史的記録なので書き換えない。

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] なし（🟢 範囲のみのため人間の事前作業は不要）

### Phase 1: ディレクトリ・ファイルの rename [AI🤖]
- [ ] `git mv Sources/Translate Sources/Translator`
- [ ] `git mv Sources/Translator/App/TranslateApp.swift Sources/Translator/App/TranslatorApp.swift`

### Phase 2: ソースコードの表示名・シンボル変更 [AI🤖]
- [ ] `TranslatorApp.swift`: `struct TranslateApp` → `struct TranslatorApp`、`MenuBarExtra("Translate", ...)` → `"Translator"`、`Button("Translate を終了")` → `"Translator を終了"`
- [ ] `Support/Log.swift`: `/tmp/translate.log` → `/tmp/translator.log`
- [ ] `Selection/ScreenshotCapture.swift`: 一時ファイル接頭辞 `translate-shot-` → `translator-shot-`
- [ ] （`KeychainStore.swift` の `service` と `HistoryStore.swift` のパス文字列は**据え置き**＝触らない）

### Phase 3: ビルド構成・スクリプトの変更 [AI🤖]
- [ ] `project.yml`: `name: Translate` → `Translator`、target 名 `Translate` → `Translator`、scheme 名 `Translate` → `Translator`（`PRODUCT_BUNDLE_IDENTIFIER` は据え置き）
- [ ] `.mise.toml`: `-scheme Translate`、`killall Translate`、`open .../Translate.app`、`open /Applications/Translate.app`、description 中の「Translate」をすべて `Translator` に
- [ ] `scripts/build-release.sh`: `APP_NAME="Translate"` / `SCHEME="Translate"` → `Translator`
- [ ] `scripts/release.sh`: `APP_NAME="Translate"` / `SCHEME` 相当 → `Translator`（`BUNDLE_ID` / `GITHUB_REPO` / `CASK_TOKEN` は据え置き）

### Phase 4: ドキュメント更新 [AI🤖]
- [ ] `VERIFY.md`: `Translate.app`、`pgrep -x Translate`、`killall Translate`、`xcodebuild ... -scheme Translate`、`build/Translate.zip`、Info.plist パス等を `Translator` に追従
- [ ] `CLAUDE.md`: アプリ名に言及する固有名詞があれば更新（「翻訳ツール」等の一般語はそのまま）

### Phase 5: ビルド & 自己検証 [AI🤖]
- [ ] `xcodegen generate`（新 target 名で `.xcodeproj` 再生成）
- [ ] `mise run build`（or `xcodebuild -scheme Translator ... build`）が通ることを確認
- [ ] `mise run run` で起動 → `pgrep -x Translator` でプロセス生存確認、`/tmp/translator.log` にログが出ることを確認
- [ ] 残存チェック: `grep -rn "Translate" --include="*.swift" --include="*.yml" --include="*.toml" --include="*.sh" --include="*.md"` で、意図せぬ `Translate`（＝アプリ名由来のもの）が残っていないか確認（機能名の `Translation`/`backTranslate` 等は除外）

### 動作確認 [人間👨‍💻]
- [ ] メニューバーのメニュー/終了項目が「Translator」表示になっている
- [ ] ショートカットで翻訳パネルが開き、翻訳が動く（＝Keychain の APIキーが据え置きで生きている）
- [ ] アクセシビリティ/画面収録の権限ダイアログが**再表示されない**（＝Bundle ID 据え置きで TCC 許可が保持されている）
- [ ] 翻訳履歴が以前のまま見える（＝履歴パス据え置き）

## ログ
### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
