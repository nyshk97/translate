#!/bin/bash
# Translate リリーススクリプト
# 使い方: ./scripts/release.sh [patch|minor|major|<x.y.z>]   （省略時は patch）
#
# 1. project.yml の MARKETING_VERSION を bump（CURRENT_PROJECT_VERSION はタイムスタンプ）
# 2. build-release.sh で署名 + notarize + staple 済みの build/Translate.zip を作成
# 3. バージョン更新を commit して main に push
# 4. GitHub Release（v<version>）を作成し ZIP を添付
# 5. nyshk97/homebrew-tap の Casks/translate-mac.rb を作成/更新
# 6. ローカルの tap を同期
#
# notarize（失敗しやすい工程）を push より前に置く。失敗時は project.yml の
# 変更がローカルに残るだけで remote には何も反映されない（`git checkout project.yml` で戻せる）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ===== 設定 =====
APP_NAME="Translate"
BUNDLE_ID="com.d0ne1s.translate"
GITHUB_REPO="nyshk97/translate"
TAP_REPO="nyshk97/homebrew-tap"
CASK_TOKEN="translate-mac"          # macOS 標準 Translate との混同を避けるため別トークン
CASK_PATH="Casks/${CASK_TOKEN}.rb"
DIST_ZIP="$REPO_ROOT/build/$APP_NAME.zip"

# ===== バージョン計算 =====
# grep -m1 で先頭マッチ後に grep 自身が終了する（`grep | head -1` は pipefail 下で SIGPIPE 誤判定の恐れ）。
CURRENT_VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*MARKETING_VERSION: *//' | tr -d '"' | tr -d ' ')"
echo "現在のバージョン: $CURRENT_VERSION"

BUMP="${1:-patch}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  [0-9]*.[0-9]*.[0-9]*) IFS='.' read -r MAJOR MINOR PATCH <<< "$BUMP" ;;
  *) echo "不正なバージョン指定: $BUMP（patch|minor|major|x.y.z）"; exit 1 ;;
esac
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
TAG="v$NEW_VERSION"
echo "新しいバージョン: $NEW_VERSION (build $BUILD_NUMBER)"

# ===== リリース前チェック =====
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 作業ツリーに未コミットの変更があります。コミットしてから実行してください。"
  git status --short
  exit 1
fi
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "❌ リリース $TAG は既に存在します。"
  exit 1
fi

# ===== project.yml 更新 =====
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$NEW_VERSION\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

# ===== ビルド + 署名 + notarize（remote 反映前に実施）=====
bash "$REPO_ROOT/scripts/build-release.sh"

if [ ! -f "$DIST_ZIP" ]; then
  echo "❌ 配布 ZIP が見つかりません: $DIST_ZIP"
  exit 1
fi
SHA256="$(shasum -a 256 "$DIST_ZIP" | awk '{print $1}')"

# ===== commit + push =====
git add project.yml
git commit -m "chore: bump version to $TAG"
git push origin main

# ===== GitHub Release =====
echo "🚀 GitHub Release を作成中..."
gh release create "$TAG" "$DIST_ZIP" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --generate-notes

# ===== Cask 更新（nyshk97/homebrew-tap）=====
echo "🍺 Cask $CASK_PATH を更新中..."
CASK_CONTENT="$(cat <<CASK
cask "$CASK_TOKEN" do
  version "$NEW_VERSION"
  sha256 "$SHA256"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/$APP_NAME.zip"
  name "$APP_NAME"
  desc "自分専用の macOS ネイティブ翻訳ツール"
  homepage "https://github.com/$GITHUB_REPO"

  depends_on macos: ">= :sonoma"

  app "$APP_NAME.app"

  zap trash: [
    "~/Library/Application Support/$BUNDLE_ID",
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]
end
CASK
)"

ENCODED="$(printf '%s' "$CASK_CONTENT" | base64)"
EXISTING_SHA="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha' 2>/dev/null || true)"
if [ -n "$EXISTING_SHA" ]; then
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" \
    --method PUT \
    --field message="chore: $CASK_TOKEN $NEW_VERSION" \
    --field content="$ENCODED" \
    --field sha="$EXISTING_SHA" \
    --silent
else
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" \
    --method PUT \
    --field message="feat: add $CASK_TOKEN $NEW_VERSION" \
    --field content="$ENCODED" \
    --silent
fi

# ===== ローカル tap 同期 =====
TAP_DIR="$(brew --repository "$TAP_REPO" 2>/dev/null || true)"
if [ -n "$TAP_DIR" ] && [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only --quiet origin main || true
fi

echo ""
echo "✅ リリース完了: $TAG"
echo "   asset : https://github.com/$GITHUB_REPO/releases/download/$TAG/$APP_NAME.zip"
echo "   sha256: $SHA256"
echo "   cask  : $TAP_REPO $CASK_PATH"
echo ""
echo "初回リリース後は Brewfile に次の行を追加:  cask 'nyshk97/tap/$CASK_TOKEN'"
