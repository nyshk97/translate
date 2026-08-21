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
- モデル: テキスト=`openai/gpt-oss-120b`（Groq・`reasoning_effort: low`）/ Vision=`gemini-2.5-flash`（Gemini）
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

### モデル差し替え（Groq）

テキスト翻訳のモデルを変更・廃止対応したときに確認する。

```sh
KEY=$(security find-generic-password -s "com.d0ne1s.translate" -a "groq-api-key" -w)
curl -s https://api.groq.com/openai/v1/models -H "Authorization: Bearer $KEY" | jq -r '.data[].id'  # 現行一覧
python3 scripts/bench-models.py <model-id>   # 実プロンプトで TTFT・出力を実測（省略時は現行モデル）
```
- pass: 採用モデルが一覧に存在し、`ttf_content` が 0.5s 以下、出力に `<think>` 等の reasoning が混入していない、両方向とも自然な訳文。
- reasoning モデルの注意（gpt-oss は `reasoning_effort: low` 必須 / qwen は `<think>` 混入）は CLAUDE.md「Groq モデル差し替えの知見」を参照。

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

### リリース成果物（署名 / Hardened Runtime / notarize / Sparkle / Cask）

リリース手順や署名・配布まわりを触ったときに確認する。

- `scripts/build-release.sh`: Release ビルド → Sparkle.framework を inside-out に Developer ID 再署名 → notarize → staple → `build/Translator.zip` を生成（公証済みアーティファクトを作るまで）。
- `scripts/release.sh [patch|minor|major|x.y.z]`（= `mise run release`）: CHANGELOG の `[Unreleased]` 確認 → bump + CHANGELOG 切り出しを commit → build-release.sh → EdDSA 署名 + `build/appcast.xml` → push → GitHub Release（ZIP + appcast、ノートは CHANGELOG）→ `nyshk97/homebrew-tap` の `Casks/translate-mac.rb` を更新。**Claude Code のセッションから叩いてよい**（画面ロック中だけ事前チェックで止まる。push 前に失敗したら bump commit は trap で巻き戻る）。

**リリースノートは `docs/CHANGELOG.md` の `[Unreleased]` から作る**（GitHub Release の本文と Sparkle の更新ダイアログの両方）。叩く前にセッションが `git log <前回タグ>..HEAD` を読んで `[Unreleased]` を埋めて commit する（書き方は CHANGELOG 冒頭）。空のまま叩くと事前チェックで止まる（`python3 scripts/changelog.py check` で単体確認できる）。

notarize を撃たずに「署名 + Hardened Runtime + Sparkle の再署名 + feed URL」を検証する（push 等の副作用なし）:

```sh
bash scripts/build-release.sh --skip-notarize    # 末尾に ✅ --skip-notarize: 署名検証まで完了
```
- 中で `codesign --verify --deep --strict`、Sparkle 構成物（Downloader.xpc / Installer.xpc / Updater.app / Autoupdate / framework）の adhoc 残存と secure timestamp、成果物 plist の `SUFeedURL` = 配信先、`SUPublicEDKey` の有無を見ている。
- Debug は `runtime` フラグが無いのが正常（Release のみ有効化。Debug はデバッガ接続のため無効）。

Sparkle はローカル版（Debug）では動かない（コードの `#if !DEBUG` と、plist の feed が Release 構成限定の二重防御）:

```sh
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' .build/Build/Products/Debug/Translator.app/Contents/Info.plist     # → 空文字
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' build/Build/Products/Release/Translator.app/Contents/Info.plist    # → feed URL
```
- ローカル版のメニューでは「アップデートを確認…」が無効化されている。

Release ビルドが Sparkle 込みで起動するか（常用版と bundle id が同じなので一旦止める）:

```sh
killall Translator; open build/Build/Products/Release/Translator.app; sleep 4
pgrep -fl 'Release/Translator.app'        # 生きていれば OK
killall Translator; open /Applications/Translator.app
```

リリース後: `gh release view v<ver> --repo nyshk97/translate --json body` が CHANGELOG の該当セクション、
`curl -sL https://github.com/nyshk97/translate/releases/latest/download/appcast.xml` の `<description>` に同じ内容。
旧版（Sparkle 未搭載の 0.1.10 以前）には更新が届かないので、その 1 回だけ `brew upgrade translate-mac` で入れる。

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
