#!/bin/bash
# Builds UTUVO Mouse and packages build/UTUVO Mouse.app
#
# Local, rebuildable candidate only: ad-hoc signing, no notarisation, nothing is
# copied into /Applications and no installer is produced.
#
# Build modes:
#   BUILD_MODE=dev      (default) The release may be unconfigured: the app then
#                        ships without a signing key, the updater stays off and
#                        the interface says so.
#   BUILD_MODE=release  The release has to be configured: an HTTPS appcast feed
#                        and a valid Ed25519 public key. Otherwise the build
#                        fails instead of shipping something unusable.
#
# Task specific environment (never written into this repository):
#   SU_FEED_URL       overrides the appcast feed
#   SU_PUBLIC_ED_KEY  the Ed25519 public key, base64 of 32 bytes. The private
#                     key stays in the protected local Keychain; only the
#                     public key is included in source and app metadata.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
BUILD_MODE="${BUILD_MODE:-dev}"
APP_NAME="UTUVO Mouse"
BUILD_DIR="${BUILD_DIR:-build}"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE="UTUVO Mouse"
BUNDLE_ID="com.utuvo.mouse"
SHORT_VERSION="0.3.3"
BUILD_VERSION="11"
DEFAULT_FEED_URL="https://github.com/mickyyang-1407/utuvo-mouse/releases/latest/download/appcast.xml"
SPARKLE_LICENSE_SHA="389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe"

case "$BUILD_MODE" in
    dev|release) ;;
    *) echo "BUILD_MODE 只能是 dev 或 release" >&2; exit 1 ;;
esac

# --- release configuration ----------------------------------------------------

FEED_URL="${SU_FEED_URL:-$DEFAULT_FEED_URL}"
PUBLIC_KEY="${SU_PUBLIC_ED_KEY:-}"
if [ -z "$PUBLIC_KEY" ] && [ -f "config/updater-public-key.txt" ]; then
    PUBLIC_KEY="$(tr -d ' \t\r\n' < "config/updater-public-key.txt")"
fi

# A public key is base64 of 32 raw bytes. Nothing else is accepted.
valid_public_key() {
    [ -n "$1" ] || return 1
    python3 - "$1" <<'PY'
import base64, sys
try:
    data = base64.b64decode(sys.argv[1].strip(), validate=True)
except Exception:
    sys.exit(1)
sys.exit(0 if len(data) == 32 else 1)
PY
}

# The feed has to be a real HTTPS URL with a host. `https:///appcast.xml` has no
# host and is refused, with or without a public key.
valid_feed_url() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
url = sys.argv[1].strip()
try:
    parsed = urlparse(url)
except ValueError:
    sys.exit(1)
sys.exit(0 if parsed.scheme == "https" and parsed.netloc and parsed.hostname else 1)
PY
}

if ! valid_feed_url "$FEED_URL"; then
    echo "更新來源必須是 HTTPS 且要有主機名稱：$FEED_URL" >&2
    exit 1
fi

if valid_public_key "$PUBLIC_KEY"; then
    KEY_STATE="ok"
else
    KEY_STATE="missing"
    if [ -n "$PUBLIC_KEY" ]; then
        KEY_STATE="invalid"
        echo "!! 提供的更新簽章金鑰格式不正確（需要 base64 的 32 位元組 Ed25519 公鑰）"
    fi
fi

if [ "$BUILD_MODE" = "release" ]; then
    if [ "$KEY_STATE" != "ok" ]; then
        echo "發行模式需要有效的更新簽章金鑰（SU_PUBLIC_ED_KEY）。目前：$KEY_STATE" >&2
        echo "本機開發請用 BUILD_MODE=dev，那時更新器會維持關閉並在畫面上說明原因。" >&2
        exit 1
    fi
fi

# --- build --------------------------------------------------------------------

echo "==> swift build -c $CONFIGURATION"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BIN_DIR/$EXECUTABLE"
if [ ! -x "$BIN_PATH" ]; then
    echo "找不到執行檔：$BIN_PATH" >&2
    exit 1
fi

SPARKLE_FRAMEWORK="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "找不到 Sparkle.framework：$SPARKLE_FRAMEWORK" >&2
    exit 1
fi

# --- package ------------------------------------------------------------------

echo "==> packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

# SwiftPM's generated Bundle.module accessor looks in Bundle.main.resourceURL.
# Keep its exact generated name beside the app, so relocation needs no build-tree fallback.
LOCALIZATION_BUNDLE="$BIN_DIR/UTUVOMouse_UTUVOMouseLocalization.bundle"
if [ ! -d "$LOCALIZATION_BUNDLE" ]; then
    echo "找不到 SwiftPM 語言資源：$LOCALIZATION_BUNDLE" >&2
    exit 1
fi
ditto "$LOCALIZATION_BUNDLE" "$APP_BUNDLE/Contents/Resources/UTUVOMouse_UTUVOMouseLocalization.bundle"

# ditto keeps the symlinks and the executable bits of the framework.
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# The app finds the framework through its own Frameworks directory.
if ! otool -l "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
fi

# The public key is only written when it is a real key. A missing key is not
# shipped as a placeholder: the updater stays off and says why.
if [ "$KEY_STATE" = "ok" ]; then
    KEY_PLIST="    <key>SUPublicEDKey</key>
    <string>$PUBLIC_KEY</string>
"
else
    KEY_PLIST=""
    echo "==> 更新簽章金鑰尚未設定：這個 App 會以『未設定發行』狀態執行，更新器不會啟動。"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hant</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>UTUVO</string>
    <key>SUFeedURL</key>
    <string>$FEED_URL</string>
    <key>SUEnableAutomaticChecks</key>
    <false/>
    <key>SUEnableSystemProfiling</key>
    <false/>
$KEY_PLIST</dict>
</plist>
PLIST

# Include notices with every locally built app, including standalone copies.
cp LICENSE THIRD-PARTY-NOTICES.md "$APP_BUNDLE/Contents/Resources/"
cp -R LICENSES "$APP_BUNDLE/Contents/Resources/"

# The full Sparkle license travels with the app, including the external
# licenses of the bundled components.
SPARKLE_LICENSE_SOURCE=".build/checkouts/Sparkle/LICENSE"
if [ -f "$SPARKLE_LICENSE_SOURCE" ]; then
    ACTUAL_SHA="$(shasum -a 256 "$SPARKLE_LICENSE_SOURCE" | awk '{print $1}')"
    if [ "$ACTUAL_SHA" != "$SPARKLE_LICENSE_SHA" ]; then
        echo "Sparkle 授權檔與稽核過的版本不符：$ACTUAL_SHA" >&2
        exit 1
    fi
fi
cp LICENSES/Sparkle-BSD.txt "$APP_BUNDLE/Contents/Resources/Sparkle-LICENSE.txt"

# --- sign, inside out ---------------------------------------------------------

# Every nested item is signed on its own before the item that contains it.
# `--deep` is only used to verify the finished bundle, never to sign it.
sign_item() {
    local item="$1"
    if ! codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$item" 2>/dev/null; then
        codesign --force --sign - --timestamp=none "$item"
    fi
    codesign --verify --strict "$item"
}

FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_BIN="$FRAMEWORK/Versions/B"

echo "==> signing inside out"
# The XPC services of Sparkle.
for xpc in "$FRAMEWORK_BIN/XPCServices/Downloader.xpc" "$FRAMEWORK_BIN/XPCServices/Installer.xpc"; do
    if [ -d "$xpc" ]; then
        sign_item "$xpc/Contents/MacOS/$(basename "${xpc%.xpc}")"
        sign_item "$xpc"
    fi
done
# The autoupdate helper.
if [ -f "$FRAMEWORK_BIN/Autoupdate" ]; then
    sign_item "$FRAMEWORK_BIN/Autoupdate"
fi
# The updater application.
if [ -d "$FRAMEWORK_BIN/Updater.app" ]; then
    sign_item "$FRAMEWORK_BIN/Updater.app/Contents/MacOS/Updater"
    sign_item "$FRAMEWORK_BIN/Updater.app"
fi
# The framework itself.
sign_item "$FRAMEWORK_BIN/Sparkle"
sign_item "$FRAMEWORK"
# And last the app itself.
sign_item "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# --- verify -------------------------------------------------------------------

echo "==> 檢查"
echo "    版本      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist"))"
echo "    架構      $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE")"
echo "    框架架構  $(lipo -archs "$FRAMEWORK_BIN/Sparkle")"
echo "    連結      $(otool -L "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" | grep -c '@rpath/Sparkle.framework') 筆 Sparkle"
echo "    rpath     $(otool -l "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE" | grep -A2 LC_RPATH | grep '@executable_path/../Frameworks' | tr -d ' ' | head -1)"
echo "    符號      $(codesign -dv "$APP_BUNDLE" 2>&1 | grep -E '^Signature' | tr -d '\n')"
echo "    金鑰      $([ "$KEY_STATE" = ok ] && echo '已設定' || echo '未設定（更新器不會啟動）')"

echo "==> 完成：$APP_BUNDLE"
du -sh "$APP_BUNDLE" | awk '{print "    大小 " $1}'
echo "    啟動：open \"$APP_BUNDLE\""
echo "    唯讀掃描：\"$APP_BUNDLE/Contents/MacOS/$EXECUTABLE\" --probe"
