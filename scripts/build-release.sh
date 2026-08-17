#!/bin/bash
# Translator リリース成果物ビルドスクリプト
#
# Release 構成でビルド → Developer ID 署名（project.yml の Manual 署名 + Hardened Runtime）
# → notarize → staple → 配布用 ZIP（ditto）を作る。
# 出力: build/Translator.zip と、その sha256 を標準出力に表示する。
#
# バージョン更新・GitHub Release・Cask 更新は release.sh が担当する。
# このスクリプトの責務は「公証済みの配布アーティファクトを作る」まで。
#
# --skip-notarize: 署名検証まで実行して終了する（notarize / staple / 配布 ZIP をスキップ）。
#     署名まわりの変更を、リリース本番より前に自走検証する用。daw/scripts/build.sh と同じフラグ。

set -euo pipefail

SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    *) echo "不明な引数: ${arg}（使えるのは --skip-notarize のみ）" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ===== 設定 =====
APP_NAME="Translator"
SCHEME="Translator"
TEAM_ID="VYDUR99LAM"
# 署名 ID のハッシュはマシンごとに異なるため直書きしない。Team ID で絞って keychain から解決する
# （keychain に他 Team の Developer ID があっても誤爆しない）。
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' "/Developer ID Application.*\\($TEAM_ID\\)/ {print \$2; exit}")"
if [ -z "$SIGN_IDENTITY" ]; then
  echo "❌ Developer ID Application（Team ${TEAM_ID}）の証明書が keychain にありません。" >&2
  echo "   Xcode → Settings → Accounts → Manage Certificates から取得してください。" >&2
  exit 1
fi
# notarytool の keychain プロファイル（自作 Mac アプリ全体で共通）。中身は App Store Connect の API キー。
# 未作成の場合: xcrun notarytool store-credentials nyshk97-notary \
#   --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \
#   --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522
NOTARY_PROFILE="${NOTARY_PROFILE:-nyshk97-notary}"

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

if [ "$SKIP_NOTARIZE" = 1 ]; then
  echo ""
  echo "✅ --skip-notarize: 署名検証まで完了（notarize / staple / 配布 ZIP はスキップ）"
  echo "   app: $APP_PATH"
  echo "   署名 ID: $SIGN_IDENTITY"
  exit 0
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
