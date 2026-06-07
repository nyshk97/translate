# macOS ネイティブ翻訳ツール（初動最速ランチャー）

## 概要・やりたいこと

自分専用の macOS ネイティブ翻訳ツールを作る。メニューバー常駐＋グローバルショートカットで即呼び出すランチャー1画面アプリ。

最優先は**「ショートカットを押した瞬間に最初のトークンが出る」初動の体感速度**。総生成時間ではなく TTFT 体感を最大化し、初動までの周辺処理（言語判定・コネクション確立・UI描画）をすべて削る。当面は英↔日中心、汎用性より自分の用途に振り切る。

コア機能: 選択テキスト翻訳 / 戻し訳チェック / スクショ・画像翻訳（vision）/ ローカル履歴（一覧＋検索）/ 設定。
v1で軽量に作れる派生（戻し訳・トーン2案・ニュアンス調整）も含める。重い経路（要約・詳しい解説）は後回し。

## 前提・わかっていること

### プロバイダー / モデル
- **テキスト（初動最速経路）**: Groq・**`llama-3.3-70b-versatile`**（Console の Multilingual カテゴリに掲載。70B級・品質重視で確定）。OpenAI互換 SSE でストリーミング。Groq はモデルが大きくても TTFT が小さいため品質と初動を両立
  - 代替候補: `Llama 4 Scout`（より新しく高速な MoE。品質に不満が出たら試す）
  - **避ける**: GPT OSS 120B/20B・Qwen 3 32B 等の reasoning 系（本文前に思考トークンを吐き TTFT が悪化するため、初動最速の翻訳経路には不向き）
- **Vision（スクショ/画像）**: Gemini Flash。テキストとは**別系統・「待つ前提」**で設計（初動最速方針はテキスト経路にのみ適用）
- **重い経路（要約・詳しい解説の高性能モデルルーティング）**: v1では作らない（後回し）
- API キーは Groq / Google の2本。**Keychain 保存**（平文で置かない）

### 入力取得
- **選択テキスト**: 合成 Cmd+C 送信 → pasteboard 読取 → **元クリップボードを復元**。Accessibility 権限が必要。Electron/Web ビュー含めほぼ全アプリで動く互換性最優先方式
- **スクショ**: `screencapture -i` の OS 標準範囲選択UIを使う → temp 保存 → Gemini へ。画像のパネルへのペースト/ドロップも同じ vision 経路で対応
- **言語判定**: ローカル文字種判定のみ（LLM を呼ばない）。ひらがな/カタカナを含めば日本語入力とみなし英訳、含まなければ和訳。判定は「日本語か否か」の2値だけ
- **方向の手動オーバーライド**: 文字種判定が外れたとき用（例: 漢字のみの日本語）にパネルへ反転トグルを置く

### ショートカット
- **KeyboardShortcuts (SPM)** を使用（録音UI＋永続化＋Carbon登録を一括）
- 既定キー: **⌘H＝翻訳**（選択ありで即翻訳／無しで空ランチャー）、**⌘⇧H＝スクショ翻訳**
  - 既知のトレードオフ: ⌘H はシステムの「隠す（Hide）」を全アプリで上書きする。承知の上。録音UIで後から変更可
- グローバルホットキーは2つ

### UI / パネル
- メニューバー常駐（`NSStatusItem`）＋ Spotlight風・画面中央上寄りの `NSPanel`。Esc / 外クリックで閉じる
- **編集可能なソース欄**（選択テキストはここに流し込む。選択・手動入力を統一）＋ ストリーミング出力欄
- ストリーミング描画は **30〜50ms バッファ**してから state 更新（トークン毎再描画のカクつき回避）
- 結果は**明示コピー（Enter / ⌘C）**。元クリップボードは復元したまま
- ボタン: **戻し訳** / **トーン2案（フォーマル・カジュアル）** / **ニュアンス調整（プリセット＋自由欄）**
- ニュアンス・トーンは英訳・和訳どちらの方向でも動く
- **履歴**: SQLite（OS同梱 libsqlite3、外部依存なし）。ランチャー内の軽い一覧＋インクリメンタル検索。書き込みはバックグラウンドで初動に影響させない

### アプリ / 基盤
- Swift / SwiftUI（必要に応じて AppKit）。**XcodeGen**（`project.yml` が source-of-truth、`.xcodeproj` は生成物=gitignore）
- 最低 macOS: **14.0 Sonoma**（SMAppService・モダンSwiftUI の下限。開発環境は macOS 26 で余裕あり）
- **ログイン時自動常駐 ON デフォルト**＋設定でトグル（SMAppService）
- 起動時＋パネル表示時に Groq/Gemini のコネクションをウォームアップ（TLS/HTTP2 往復を消す）
- ネイティブ HTTP（`URLSession`）。CORS/プリフライト対策は不要
- ローカル完結・個人用。署名/notarize/Sparkle なし。非アクティブ時はバックグラウンド処理を止める

### 非目標（やらない）
Web版 / 多言語UI / 中間サーバー / 認証・課金・複数ユーザー / 重い汎用抽象化・プラグイン機構 / 添削・校正 / 発音再生 / AI返信作成 など（CLAUDE.md「不要」リスト準拠）

## 実装計画

### 事前準備 [人間👨‍💻]
- [x] Groq の API キーを取得する（console.groq.com）→ Keychain 格納済み（account=`groq-api-key`）
- [x] Google AI Studio で Gemini の API キーを取得する（aistudio.google.com）→ Keychain 格納済み（account=`gemini-api-key`）。Phase 4 で使用
- [x] `xcodegen` / `mise` が入っているか確認（無ければ Brewfile 経由で追加）→ xcodegen 2.45.4 / mise / Xcode 26.5 / Swift 6.3.2 確認

### Phase 0: プロジェクト基盤 [AI🤖]
- [x] `project.yml`（XcodeGen）作成: macOS app、最低 macOS 14.0、`LSUIElement`/accessory 設定、KeyboardShortcuts(v1.10.0) の SPM 依存、`schemes:` 明示
- [x] `.mise.toml`（主要 [tasks] に日本語 description: regen/build/run/kill）
- [x] `.gitignore`（`*.xcodeproj`, `Generated/`, `.build/` 等）
- [x] メニューバー常駐スケルトン: accessory policy、メニューバーアイコン、空の `NSPanel`（Spotlight風・中央表示・Esc/外クリックで閉じる）
- [x] 設定画面の器（SwiftUI Settings シーン）: APIキー入力欄（Keychain保存）・ホットキー録音(KeyboardShortcuts.Recorder)・ログイン項目トグル(無効プレースホルダ)
- [x] Keychain ラッパ（Groq/Gemini キーの保存・読出）
- [x] ビルド＆起動確認: BUILD SUCCEEDED・常駐プロセス生存・LSUIElement=true 確認（メニューバー目視とパネル開閉はユーザー確認待ち）

### Phase 1前の準備 [人間👨‍💻]
- [x] アプリに Accessibility 権限を付与（合成 Cmd+C と グローバルホットキーに必要）→ 付与済み。署名を安定 ID にしたため以降のリビルドでも保持される

### Phase 1: テキスト翻訳コア（初動最速経路）[AI🤖]
- [x] ローカル言語判定（ひらがな/カタカナ/半角カナ有無の2値）`LanguageDetector`
- [x] Groq ストリーミングクライアント（`URLSession.bytes`、OpenAI互換 SSE パース、短い固定プロンプト）`TranslationService`
- [x] ウォームアップ（起動時＋パネル表示時に `/v1/models` GET でコネクション温め）
- [x] 選択テキスト取得（合成 Cmd+C → pasteboard 読取 → 元クリップボード全タイプ復元）`SelectionCapture`、Accessibility 権限プロンプト含む
- [x] ⌘H ホットキー登録: 開いていればトグルで閉じ、閉じていれば選択取得→即翻訳／選択無しは空ランチャー
- [x] パネルUI: 編集可能ソース欄＋ストリーミング出力欄、40msバッファ描画、方向反転トグル、`.preferredContentSize`＋上端固定で出力に追従
- [x] 結果の明示コピー（⌘C）。手動翻訳は ⌘Return（Return は改行のため）。中断可能な非ブロッキング動作
- [x] エラー表示（キー未設定・APIエラーをパネル内に赤字表示）
- [x] 動作確認: 日本語選択→⌘H→英訳 / 英語選択→和訳 / Esc / ⌘C / クリップボード復元（クロバー対策込み3回連続）すべて確認済み

### Phase 2: 戻し訳・トーン・ニュアンス [AI🤖]
- [x] 戻し訳ボタン（出力を逆方向にもう一度ストリーム翻訳。`backTranslate`）
- [x] トーン2案ボタン（フォーマル→カジュアルを順にストリーム。`generateTones`、デフォルトでは出さない）
- [x] ニュアンス調整（プリセット4種＋自由テキスト欄→ `translate(instruction:)` で再翻訳）
- [x] 各機能が英訳・和訳どちらの方向でも動くことを確認（A→あ / あ→A 両方で検証済み）
- 実装: `TranslationService.stream` に `instruction` 引数を追加し方向プロンプトに追記。アクション行は主翻訳完了後に表示、結果欄はデータ駆動で自動可視化

### Phase 3: ローカル履歴（SQLite）[AI🤖]
- [x] libsqlite3 薄ラッパ＋スキーマ（actor `HistoryStore` で直列化。入力・出力・方向・モデル・日時）。DB は `~/Library/Application Support/com.d0ne1s.translate/history.sqlite`
- [x] 翻訳確定時に `Task.detached` でバックグラウンド追記（初動を阻害しない。直前と同一は重複登録しない）
- [x] ランチャー空状態で一覧＋インクリメンタル検索（120ms デバウンス）、行クリックで API を呼ばず呼び戻し
- [x] 動作確認: 翻訳が残る（DB 行数で確認）・検索で引ける・呼び戻せる

### Phase 4前の準備 [人間👨‍💻]
- [x] アプリに画面収録（Screen Recording）権限を付与（`screencapture -i` の初回）→ 付与済み

### Phase 4: Vision 経路（スクショ・画像）[AI🤖]
- [x] `screencapture -i -x` を Process で起動 → temp PNG → 読み込み（`ScreenshotCapture`、キャンセル時は nil）
- [x] Gemini ストリーミングクライアント（`gemini-2.5-flash`、`streamGenerateContent?alt=sse`、画像＋固定プロンプト）`GeminiService`。起動時ウォームアップも追加
- [x] ⌘⇧H ホットキー登録 → スクショ翻訳フロー（パネルに画像サムネイル＋ストリーミング訳、履歴にも記録）
- [x] ~~パネルへの画像ペースト/ドロップ~~ → **削除**。Spotlight 風パネルは外クリックで閉じるため Finder からのドラッグでパネルが消える／ファイルのペーストはパス文字列が入るだけで実用不可。ユーザー判断で不要のため撤去
- [x] 動作確認: 画面範囲選択 → 翻訳 を確認済み（外国語→日本語 / 日本語→英語、モデルが方向を吸収）

### Phase 5: 仕上げ・常駐最適化 [AI🤖]
- [x] ログイン項目（SMAppService）`LoginItem`。初回起動時に ON（`loginItemConfigured` フラグ）＋設定一般タブのトグルで切替
- [x] 設定画面の実装完成（APIキー secure 入力→Keychain ✓、ホットキー録音 ✓、ログイン項目トグル ✓）
- [x] 非アクティブ時のバックグラウンド処理停止: タイマー無し・`hide()` で全 Task を cancel。アイドル CPU ~0.0% / RSS ~80MB を実測
- [x] 既存の初動速度: ウォームアップ（起動時＋パネル表示時）健在。AX 経路で選択取得も高速化
- 注意: dev ビルド（`.build/...`）から register するとログイン項目はその dev パスを指す。実利用時は Release を /Applications に置いて再登録する

### 動作確認 [人間👨‍💻]
- [x] 各アプリで選択翻訳が効くか（AXSelectedText / AXPress(Copy) 経路で確認。ターミナル等も可）
- [x] 初動の体感速度が満足できるか → 満足
- [x] スクショ翻訳の品質（⌘⇧H 経路で確認）
- [x] ログイン後に自動常駐するか → ログイン項目 ON（登録済み）
- [x] ⌘H の Hide 上書きが許容範囲か → 許容（気になれば録音UIで再割当）

## ログ
### 試したこと・わかったこと
- Groq Console のモデル一覧で `llama-3.3-70b-versatile`（Multilingual）を確認 → テキスト経路の確定モデルに採用
- KeyboardShortcuts は最新 v1.10.0。`KeyboardShortcuts.Name` が Sendable 非準拠で Swift 6 strict concurrency が `static let` を弾く → `nonisolated(unsafe) static let` でオプトアウトしてビルド通過
- SourceKit のインライン診断（`No such module 'KeyboardShortcuts'` 等）はホールモジュール索引取りこぼしで頻発するが実ビルドは通る → ビルド結果を信用
- Bash tool 側プロセスに画面収録権限が無く `screencapture` が真っ黒画像を返す → メニューバーの目視確認はユーザー依頼
- 【想定外の失敗】⌘H でパネルが出ず無反応。原因は `NSPanel.collectionBehavior` に `.canJoinAllSpaces` と `.moveToActiveSpace` を同時指定（排他で `NSInternalInconsistencyException`）。AppKit イベントハンドラ内の例外はループが握りつぶしクラッシュしないため、`sample` でスタック採取＋同一 init を CLI 再現して特定。修正: `.moveToActiveSpace` を外す。教訓: 全スペース＋フルスクリーン上は `[.canJoinAllSpaces, .fullScreenAuxiliary]`
- accessory アプリのパネルは表示後 `isKeyWindow=false` のことがあり入力できない → 開くたびに NSHostingView を載せ直し `onAppear` で `@FocusState` を立ててテキスト欄にフォーカス
- 【署名/TCC】ad-hoc 署名（`CODE_SIGN_IDENTITY: "-"`）はリビルドのたびに cdhash が変わり、TCC（アクセシビリティ）許可が毎回リセットされ「⌘H のたびに権限ダイアログ」になる。安定した署名 ID（Developer ID `VYDUR99LAM` のハッシュ直指定）に変更し、designated requirement を clean リビルドでも一致させて許可を永続化。`CODE_SIGN_IDENTITY: "Apple Development"` は macOS で "Mac Development" に解決され証明書が見つからず失敗 → ハッシュ直指定で回避。切替時は `tccutil reset Accessibility com.d0ne1s.translate`
- 【クリップボードのクロバー】合成 Cmd+C 後、復元自体は成功するのに数百ms 後にコピー元アプリ（Electron 系エディタ）が選択テキストを**遅延再書き込み**して上書きしてくる（changeCount で確認）。対策: 復元後 ~1.2s 監視し、元と違う値になったら再復元する `scheduleAntiClobber`。原因特定は `capture()` に退避/取得/復元直後/復元+400ms の値を changeCount 付きでログ出しして実施
- 【合成 Cmd+C で素の「c」が漏れる（重要）】⌘H 押下時、フォーカス欄に「c」が入力される事故。原因は **修飾キーを `keyDown/keyUp` で送っていた**こと。macOS の物理 modifier は `flagsChanged` イベントであり、C キーに `.flags=.maskCommand` を付けても対象アプリの実効 modifier 状態にならず、特にターミナル/独自入力アプリで素の「c」になる。診断: イベントの `flags` に Cmd は乗る（`cmdFlag=true`）が `changeCount` 変化せず「c」が入る＝配送時に修飾が適用されていない、と切り分け。`.cghidEventTap`/`.cgSessionEventTap` 両方・`onKeyUp`化・30ms 待機すべて無効。**識者助言で解決**: 修飾キーは `event.type = .flagsChanged` で送る＋`CGEventSource.localEventsSuppressionInterval`/`setLocalEventsFilterDuringSuppressionState` で物理キー割り込みを抑制
- 【選択取得は段階フォールバックが正解】公開 API で任意アプリの選択を確実取得する方法は無い。実装した順: ①`AXSelectedText`（最速・副作用なし）→ ②**前面アプリの menu bar から `AXMenuItemCmdChar=="C"` かつ修飾⌘のみの Copy 項目を `AXUIElementPerformAction(.AXPress)`**（キーを送らないので「c」漏れ無し）→ ③ flagsChanged 修正版 Cmd+C（Copy メニューが無いアプリのみ）。注意: Copy 項目の **`AXEnabled` はメニュー未展開だと古い値（disabled）が返る**ので選択有無の判定に使えない → 一律 AXPress して `changeCount` 変化で判定する

### 方針変更
- メニューバー常駐を生 `NSStatusItem` ではなく SwiftUI の `MenuBarExtra` シーンで実装。理由: SwiftUI App ライフサイクルと統合でき、`SettingsLink` で設定ウィンドウを開けてコードが簡潔。NSPanel 制御は `LauncherController` に分離
- 当初「署名なし（ローカル個人用）」方針だったが、ad-hoc 署名だと TCC 許可がリビルドのたびに飛ぶため **Developer ID で署名**する方針に変更。notarize / Sparkle は引き続き無し（配布しない個人用のため）
- 手動翻訳の実行キーは Enter ではなく **⌘Return**（axis:.vertical の TextField では Enter を改行に使うため）。コピーは ⌘C。選択→⌘H の主経路は自動翻訳なので実行キーは補助的
- 選択取得を「合成 Cmd+C 一本」から **AXSelectedText → AXPress(Copy) → 合成 Cmd+C の段階フォールバック**に変更。理由: 合成 Cmd+C は「c」漏れ・クロバー・修飾不適用などトラブルが多く、AX 経路はキー/クリップボードを使わず堅牢で速い。dig 時の「合成 Cmd+C」決定は実質上位互換に置き換え
- 翻訳の実行キーを ⌘Return → **Enter（修飾なし）** に変更。ランチャーでは Enter で翻訳が自然（ペーストした改行は文字列として保持される）
- 【コードレビュー対応】①手入力時に言語判定が走らない → `translate(redetect:)` を追加し手動入力では入力から方向を再判定（手動トグル/ニュアンスは維持）②キャンセル済みストリームが `isStreaming=false`/`recordHistory` を実行 → 各 Task で `await` 後に `Task.isCancelled` ガード ③anti-clobber が広すぎ直後の正当なコピーも巻き戻す → 「取得した選択テキストと一致したときだけ復元」に限定
- 【UI改善】戻し訳・トーンを薄い背景カードにして主出力と区別。長文でパネルが画面を超え下が見えない問題 → 入力欄は固定、以降を1つの `ScrollView`（maxHeight 460）にまとめてスクロール可能に（出力の入れ子 ScrollView は撤去）
