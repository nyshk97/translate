# 動作確認

変更した箇所に関係するセクションだけを選んで確認する（毎回全項目は実行しない）。

このアプリは GUI の macOS 常駐アプリで、機能の多くが Accessibility / 画面収録権限と目視に依存する。
そのため確認手順を **自走確認（Claude 単独で実行可能）** と **手動確認（ユーザー依頼）** に分けてある。

- **自走確認**: ビルド・プロセス生存・署名・履歴 DB など、Bash から検証できるもの。
- **手動確認**: パネルの表示や各アプリでのショートカット挙動など、視覚・権限・実フォーカスに依存するもの。
  - Claude の Bash プロセスには画面収録権限が無く `screencapture` が黒画像を返すため、視覚確認は自動化せずユーザーに依頼する。
  - ユーザーが手元で流す場合、このセッションでは行頭に `!` を付けるとコマンドをこのセッション内で実行できる。

## 環境・前提

- ビルド/タスク: `mise run build`（`xcodegen generate` + `xcodebuild` Debug）/ `mise run run`（ビルド + 起動）/ `mise run kill`（終了）
- ビルド成果物: `.build/Build/Products/Debug/Translator.app`
- Bundle ID: `com.d0ne1s.translate`
- 署名: Developer ID（Team `VYDUR99LAM`）の安定 ID で Manual 署名。リビルドで cdhash が変わらず TCC（Accessibility / 画面収録）許可が保持される。
- API キー: Keychain（service `com.d0ne1s.translate` / account `groq-api-key`・`gemini-api-key`）
- 履歴 DB: `~/Library/Application Support/com.d0ne1s.translate/history.sqlite`
- モデル: テキスト=`llama-3.3-70b-versatile`（Groq）/ Vision=`gemini-2.5-flash`（Gemini）
- ショートカット既定: ⌘H=翻訳 / ⌘⇧H=スクショ翻訳

---

## 自走確認（Claude 単独で実行可能）

### ビルド基盤

```sh
mise run build 2>&1 | tail -5
```
- pass: 末尾に `** BUILD SUCCEEDED **` が出る。

### プロセス常駐 / accessory 設定

```sh
mise run run            # ビルドして起動（メニューバー常駐）
pgrep -x Translator      # PID が返れば生存
/usr/libexec/PlistBuddy -c "Print :LSUIElement" \
  .build/Build/Products/Debug/Translator.app/Contents/Info.plist
```
- pass: `pgrep` が PID を返す（プロセス生存）かつ `LSUIElement` が `true`（Dock に出ない accessory アプリ）。
- 終了は `mise run kill`（`killall Translator`）。

### 署名の安定 ID（TCC 許可の永続性）

署名 ID を変えた／署名まわりを触ったときに確認する。

```sh
codesign -dr - .build/Build/Products/Debug/Translator.app 2>&1 | grep designated
```
- pass: designated requirement に `identifier "com.d0ne1s.translate"` と `subject.OU = VYDUR99LAM` が含まれる。
- 2 回クリーンリビルドして上記が一致すれば、リビルドで Accessibility 許可が飛ばないことの担保になる。
- 署名 ID を変更したときは古い TCC エントリを掃除する: `tccutil reset Accessibility com.d0ne1s.translate`

### 履歴 DB（SQLite）

履歴の保存・スキーマ・検索まわりを触ったときに確認する。

```sh
DB="$HOME/Library/Application Support/com.d0ne1s.translate/history.sqlite"
sqlite3 "$DB" ".schema history"                       # スキーマ確認
sqlite3 "$DB" "SELECT count(*) FROM history;"         # 行数
sqlite3 "$DB" "SELECT direction, model, datetime(created_at,'unixepoch','localtime') \
  FROM history ORDER BY id DESC LIMIT 3;"             # 最新3件
```
- pass: テーブル `history`（列: `id, source, output, direction, model, created_at`）が存在し、翻訳を 1 回行った後に再実行すると **行数が増える**。
- `direction` は `toJapanese` / `toEnglish`、`model` は使用モデル名が入る。
- 検索（`LIKE`）の確認: `sqlite3 "$DB" "SELECT id, source FROM history WHERE source LIKE '%<語句>%' OR output LIKE '%<語句>%' LIMIT 5;"`

### リリース成果物（署名 / Hardened Runtime / notarize / Cask）

リリース手順や署名・配布まわりを触ったときに確認する。

- `scripts/build-release.sh`: Release ビルド → Developer ID 署名 → notarize → staple → `build/Translator.zip` を生成（公証済みアーティファクトを作るまで）。
- `scripts/release.sh [patch|minor|major|x.y.z]`: バージョン bump → build-release.sh → commit/push → GitHub Release → `nyshk97/homebrew-tap` の `Casks/translate-mac.rb` を更新。

notarize を撃たずに「署名 + Hardened Runtime」だけ検証する（push 等の副作用なし）:

```sh
xcodegen generate
xcodebuild -project Translator.xcodeproj -scheme Translator -configuration Release \
  -derivedDataPath build clean build 2>&1 | tail -3      # ** BUILD SUCCEEDED **
APP="build/Build/Products/Release/Translator.app"
codesign -d --verbose=4 "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime"
```
- pass: `flags=0x10000(runtime)`（Hardened Runtime 有効＝notarize の必須要件）と `Authority=Developer ID Application: ...(VYDUR99LAM)` が出る。
- Debug は `runtime` フラグが無いのが正常（Release のみ有効化。Debug はデバッガ接続のため無効）。

notarize 済みアプリの最終確認（実際のリリース後の成果物に対して）:

```sh
xcrun stapler validate "$APP"                 # "The validate action worked!"
spctl --assess --type execute -vv "$APP"      # accepted source=Notarized Developer ID
```

---

## 手動確認（ユーザー依頼）

視覚・権限・実フォーカスに依存するため、ユーザーが目視で確認する。変更に関係する項目だけ拾う。

### テキスト翻訳コア（初動最速経路 / ⌘H）

- 他アプリでテキストを選択 → ⌘H → パネルが画面中央上寄りに即表示され、選択文がソース欄に流し込まれて翻訳がストリーミング表示される。
- 日本語を選択 → 英訳 / 英語（その他言語）を選択 → 和訳になる（ローカル文字種判定）。
- 漢字のみ等で方向が外れたら、パネルの**反転トグル**で方向を切り替えられる。
- パネルを開いた状態で ⌘H をもう一度 → トグルで閉じる。Esc / 外クリックでも閉じる。
- 選択なしで ⌘H → 空のランチャー（履歴一覧）が出る。
- 手入力 → Enter で翻訳、入力内容から方向が再判定される。
- 結果を ⌘C でコピー。**元のクリップボードが復元されている**（特に Electron 系エディタで、コピー後 ~1s しても元の値のまま＝クロバー対策が効いている）。
- 翻訳中でも入力・中断・次の操作ができる（非ブロッキング）。
- 「c」など素のキーが選択元アプリに漏れていない（合成 Cmd+C の修飾不適用バグの回帰チェック）。
- ※各アプリ対応の段階フォールバック（AXSelectedText → AXPress(Copy) → 合成 Cmd+C）。ターミナル等でも選択翻訳が効くか。

### 補助機能（戻し訳 / トーン / ニュアンス）

主翻訳の完了後にアクション行が表示される。英訳・和訳どちらの方向でも動く。

- **戻し訳**: 出力を逆方向にもう一度翻訳し、カード表示される。
- **トーン2案**: フォーマル / カジュアルが順にストリーム表示される（デフォルトでは出さない、ボタンで明示的に）。
- **ニュアンス調整**: プリセット4種＋自由テキスト欄 → 再翻訳。
- 補助機能の失敗が**主出力をエラー表示に化けさせない**（補助はカード内に `⚠️` で表示、主翻訳のみ赤字エラー）。
- 長文でもパネルが画面を超えず、入力欄固定のままスクロールで全体が見える。

### スクショ・画像翻訳（Vision / ⌘⇧H）

- ⌘⇧H → OS 標準の範囲選択 UI（十字カーソル）→ 範囲確定で、パネルに画像サムネイル＋訳がストリーミング表示される。
- 外国語→日本語 / 日本語→英語（モデルが方向を吸収）。
- Esc で範囲選択をキャンセルすると何も起きない。
- 翻訳結果が履歴にも記録される（自走確認の DB 行数増で裏取り可）。

### 履歴 UI

- 選択なしランチャーで履歴一覧が出る。検索欄に入力（120ms デバウンス）でインクリメンタルに絞り込める。
- 行クリックで API を呼ばずに過去の翻訳を呼び戻せる。

### 設定 / 常駐

- メニューバーにアイコンが表示される。
- 設定画面: API キーを secure 入力 → 保存 → Keychain に入る（再起動後も保持）。ホットキー録音 UI で再割当できる。ログイン項目トグルが効く。
- ログイン項目 ON のとき、ログイン後に自動常駐する。
  - 注意: dev ビルド（`.build/...`）から register するとログイン項目は dev パスを指す。実利用時は Release を `/Applications` に置いて再登録する。
- 非アクティブ時にバックグラウンド処理が止まる（アイドル CPU ~0%）。`hide()` で全 Task が cancel される。
