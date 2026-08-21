#!/bin/bash
# Translator リリーススクリプト
# 使い方: ./scripts/release.sh [patch|minor|major|<x.y.z>]   （省略時は patch）
#
# 0. docs/CHANGELOG.md の [Unreleased] に内容があることを確認（空なら止める）
# 1. project.yml の MARKETING_VERSION を bump（CURRENT_PROJECT_VERSION はタイムスタンプ）し、
#    CHANGELOG の [Unreleased] を [<version>] - <date> に切り出して同じ commit にする
# 2. build-release.sh で署名 + notarize + staple 済みの build/Translator.zip を作成
# 3. zip に Sparkle の EdDSA 署名を付けて build/appcast.xml を生成（CHANGELOG を <description> に）
# 4. bump commit を main に push
# 5. GitHub Release（v<version>）を作成し ZIP と appcast.xml を添付（ノートは CHANGELOG から）
# 6. nyshk97/homebrew-tap の Casks/translate-mac.rb を作成/更新し、ローカルの tap を同期
#
# notarize（失敗しやすい工程）を push より前に置く。bump はビルド前にローカルで commit し、
# push までに失敗したら trap がその commit を巻き戻す（remote も作業ツリーも実行前の状態に戻る）。
# Claude Code のセッションから叩いてよい。唯一の条件は submit の数分間に画面がロックされない
# こと（notarytool の資格情報は data-protection keychain にあり、ロック中は読めない）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ===== 設定 =====
APP_NAME="Translator"
BUNDLE_ID="com.d0ne1s.translate"
GITHUB_REPO="nyshk97/translate"
TAP_REPO="nyshk97/homebrew-tap"
CASK_TOKEN="translate-mac"          # macOS 標準 Translate との混同を避けるため別トークン
CASK_PATH="Casks/${CASK_TOKEN}.rb"
DIST_ZIP="$REPO_ROOT/build/$APP_NAME.zip"
TEAM_ID="VYDUR99LAM"
NOTARY_PROFILE="${NOTARY_PROFILE:-nyshk97-notary}"
SPARKLE_ACCOUNT="translate"
SIGN_UPDATE="$REPO_ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
APPCAST="$REPO_ROOT/build/appcast.xml"
CHANGELOG_PY="$REPO_ROOT/scripts/changelog.py"
# アプリが見に行く feed。build-release.sh が成果物の SUFeedURL と突き合わせる。
export FEED_URL="https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"

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
  *) echo "不正なバージョン指定: ${BUMP}（patch|minor|major|x.y.z）"; exit 1 ;;
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
# 複数マシンで開発しているので、ローカルの main は別クローンからのリリースで平気で遅れる。
# 遅れたまま bump すると同じバージョンを二重に切る。
git fetch -q origin --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "❌ HEAD が origin/main と一致しません（pull 忘れ / push 忘れ）。"
  echo "   local : $(git rev-parse --short HEAD)"
  echo "   origin: $(git rev-parse --short origin/main)"
  exit 1
fi
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "❌ リリース $TAG は既に存在します。"
  exit 1
fi
# リリースノートは CHANGELOG の [Unreleased] からしか作らない。空なら止める
python3 "$CHANGELOG_PY" check
# 画面ロック中は notarytool の資格情報が読めない。submit に数分かかるので始める前に止める
CONSOLE_LOCKED="$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleLocked raw -o - - 2>/dev/null || true)"
if [ "$CONSOLE_LOCKED" = "true" ]; then
  echo "❌ 画面がロックされています。解除してから実行してください。"
  exit 1
fi
# 署名証明書・notarize の資格情報・Sparkle の鍵は keychain にあり、開発機を移すと欠ける。
# 数分のビルドを終えてから落ちないよう先に見る
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
case "$IDENTITIES" in
  *"Developer ID Application"*"($TEAM_ID)"*) ;;
  *) echo "❌ Developer ID Application 証明書（${TEAM_ID}）が keychain にありません。"; exit 1 ;;
esac
if ! NOTARY_CHECK="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
  echo "❌ notarize の keychain プロファイル '$NOTARY_PROFILE' が使えません:"
  echo "$NOTARY_CHECK" | head -3
  echo "   作成: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "           --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \\"
  echo "           --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh が未認証です。gh auth login を先に済ませてください。"; exit 1
fi
if ! security find-generic-password -s "https://sparkle-project.org" -a "$SPARKLE_ACCOUNT" >/dev/null 2>&1; then
  echo "❌ Sparkle の EdDSA 秘密鍵（keychain account '$SPARKLE_ACCOUNT'）がありません。"
  echo "   復元: build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account $SPARKLE_ACCOUNT -f ~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-translate-private.key"
  exit 1
fi

# ===== バージョン更新 + CHANGELOG 切り出し（ローカル commit。push は notarize 後）=====
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$NEW_VERSION\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml
python3 "$CHANGELOG_PY" release "$NEW_VERSION" "$(date +%Y-%m-%d)"
git add project.yml docs/CHANGELOG.md
git commit -q -m "chore: bump version to $TAG"
BUMP_PUSHED=0
rollback_bump() {
  if [ "$BUMP_PUSHED" -eq 0 ]; then
    echo "↩️  失敗したので bump commit を巻き戻します（remote は未変更）"
    git reset -q --hard HEAD~1
  fi
}
trap 'rollback_bump' ERR

# ===== ビルド + 署名 + notarize（remote 反映前に実施）=====
bash "$REPO_ROOT/scripts/build-release.sh"

if [ ! -f "$DIST_ZIP" ]; then
  echo "❌ 配布 ZIP が見つかりません: $DIST_ZIP"
  exit 1
fi
SHA256="$(shasum -a 256 "$DIST_ZIP" | awk '{print $1}')"

# ===== Sparkle: EdDSA 署名 + appcast =====
[ -x "$SIGN_UPDATE" ] || { echo "❌ sign_update が見つかりません: $SIGN_UPDATE"; exit 1; }
echo "🔏 Sparkle の EdDSA 署名を付けています..."
ED_ATTRS="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DIST_ZIP")"   # sparkle:edSignature="..." length="..."
case "$ED_ATTRS" in
  *sparkle:edSignature=*) ;;
  *) echo "❌ sign_update の出力が想定外です: $ED_ATTRS"; exit 1 ;;
esac
RELEASE_NOTES_MD="$REPO_ROOT/build/release-notes-$NEW_VERSION.md"
SPARKLE_DESC_HTML="$REPO_ROOT/build/sparkle-description-$NEW_VERSION.html"
python3 "$CHANGELOG_PY" notes "$NEW_VERSION" "$RELEASE_NOTES_MD" "$SPARKLE_DESC_HTML"
PUBDATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$APP_NAME.zip"
RELEASE_URL="https://github.com/$GITHUB_REPO/releases/tag/$TAG"
# 1 item だけでよい: feed は releases/latest/download/appcast.xml で常に最新 Release の物を指す。
# sparkle:version は CFBundleVersion（タイムスタンプ）。Sparkle の新旧比較はこちらで行われる。
cat > "$APPCAST" <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$TAG</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$RELEASE_URL</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
$(cat "$SPARKLE_DESC_HTML")
]]></description>
      <enclosure url="$DOWNLOAD_URL" $ED_ATTRS type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST_EOF
xmllint --noout "$APPCAST"

# ===== push =====
git push origin main
BUMP_PUSHED=1
trap - ERR

# ===== GitHub Release =====
echo "🚀 GitHub Release を作成中..."
gh release create "$TAG" "$DIST_ZIP" "$APPCAST" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --notes-file "$RELEASE_NOTES_MD"

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

  auto_updates true
  depends_on macos: :sonoma

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
echo "   feed  : $FEED_URL"
echo "   cask  : $TAP_REPO $CASK_PATH"
