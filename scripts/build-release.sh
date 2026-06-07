#!/bin/bash
# Translator リリース成果物ビルドスクリプト
#
# Release 構成でビルド → Developer ID 署名（project.yml の Manual 署名 + Hardened Runtime）
# → notarize → staple → 配布用 ZIP（ditto）を作る。
# 出力: build/Translator.zip と、その sha256 を標準出力に表示する。
#
# バージョン更新・GitHub Release・Cask 更新は release.sh が担当する。
# このスクリプトの責務は「公証済みの配布アーティファクトを作る」まで。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ===== 設定 =====
APP_NAME="Translator"
SCHEME="Translator"
# Developer ID Application（Team VYDUR99LAM）の安定署名 ID。project.yml の CODE_SIGN_IDENTITY と一致。
SIGN_IDENTITY="85D91870B2836DB303E2224A2D8D56051F26A6FB"
# 既存の notarytool プロファイルを流用（同一 Apple ID / Team VYDUR99LAM のため新規作成不要）。
# 未作成の場合: xcrun notarytool store-credentials polepole-notary --apple-id <id> --team-id VYDUR99LAM
NOTARY_PROFILE="polepole-notary"

BUILD_DIR="$REPO_ROOT/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DIST_ZIP="$BUILD_DIR/$APP_NAME.zip"

# ===== ビルド =====
echo "🔨 Xcode プロジェクト生成 + Release ビルド..."
xcodegen generate
rm -rf "$BUILD_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  clean build

if [ ! -d "$APP_PATH" ]; then
  echo "❌ ビルド失敗: $APP_PATH が見つかりません"
  exit 1
fi

# ===== 配布用に再署名 =====
# xcodebuild の build 時署名は「開発用」で notarize 要件を満たさない:
#   - get-task-allow entitlement が付く（配布ビルドでは禁止 → Invalid）
#   - secure timestamp が無い（"Signed Time" のみ。notarize は Apple TSA の timestamp が必須 → Invalid）
# そこで Developer ID + Hardened Runtime + secure timestamp で明示的に再署名し、
# entitlements を付けない（= 空）ことで get-task-allow を除去する。このアプリは entitlement 不要。
# 埋め込み framework は無い（KeyboardShortcuts は静的リンク）ので単一バイナリの再署名で足りる。
echo "🔏 配布用に再署名（Hardened Runtime + secure timestamp、get-task-allow 除去）..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"

# ===== 署名検証（notarize 前提条件を全部チェック）=====
echo "🔏 署名を検証..."
codesign --verify --strict --verbose=2 "$APP_PATH"
# codesign 出力は一旦変数に取ってから判定する（`codesign | grep -q` 直結は grep -q の
# パイプ早期終了で codesign が SIGPIPE 終了し、set -o pipefail 下で誤検知するため）。
SIGN_INFO="$(codesign -dvvv --entitlements - "$APP_PATH" 2>&1)"
if [[ "$SIGN_INFO" != *"(runtime"* ]]; then
  echo "❌ Hardened Runtime（runtime フラグ）が無い（notarize 必須）。"; echo "$SIGN_INFO"; exit 1
fi
if [[ "$SIGN_INFO" != *"Timestamp="* ]]; then
  echo "❌ secure timestamp が無い（Signed Time のみ）。--timestamp 再署名に失敗（ネットワーク / Apple TSA を確認）。"; echo "$SIGN_INFO"; exit 1
fi
if [[ "$SIGN_INFO" == *"get-task-allow"* ]]; then
  echo "❌ get-task-allow entitlement が残存（配布ビルドでは禁止）。"; echo "$SIGN_INFO"; exit 1
fi

# ===== notarize 用 ZIP =====
# ditto を使う。zip -r は framework 内の symlink を実体化して署名を壊すため使わない。
echo "📦 notarize 用 ZIP を作成..."
NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

# ===== notarize =====
echo "📤 notarize 送信中（数分かかることがあります）..."
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ===== staple =====
echo "📎 staple 中..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ===== Gatekeeper 評価（情報表示）=====
echo "🛡  Gatekeeper 評価..."
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

# ===== 配布用 ZIP =====
echo "📦 配布用 ZIP を作成..."
rm -f "$DIST_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_ZIP"

SHA256="$(shasum -a 256 "$DIST_ZIP" | awk '{print $1}')"

echo ""
echo "✅ ビルド完了: $DIST_ZIP"
echo "   sha256: $SHA256"
