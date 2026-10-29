#!/bin/bash
# Builds UTUVO Mouse and packages build/UTUVO Mouse.app
#
# Local, rebuildable candidate only: ad-hoc signing, no notarisation, nothing is
# copied into /Applications and no installer is produced.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="UTUVO Mouse"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE="UTUVO Mouse"

echo "==> swift build -c $CONFIGURATION"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/$EXECUTABLE"
if [ ! -x "$BIN_PATH" ]; then
    echo "找不到執行檔：$BIN_PATH" >&2
    exit 1
fi

echo "==> packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hant</string>
    <key>CFBundleExecutable</key>
    <string>UTUVO Mouse</string>
    <key>CFBundleIdentifier</key>
    <string>com.utuvo.mouse</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>UTUVO Mouse</string>
    <key>CFBundleDisplayName</key>
    <string>UTUVO Mouse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>UTUVO</string>
</dict>
</plist>
PLIST

# Include notices with every locally built app, including standalone copies.
cp LICENSE THIRD-PARTY-NOTICES.md "$APP_BUNDLE/Contents/Resources/"
cp -R LICENSES "$APP_BUNDLE/Contents/Resources/"

# A failed signature must fail the build instead of producing a false success.
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> 完成：$APP_BUNDLE"
du -sh "$APP_BUNDLE" | awk '{print "    大小 " $1}'
echo "    啟動：open \"$APP_BUNDLE\""
echo "    唯讀掃描：\"$APP_BUNDLE/Contents/MacOS/$EXECUTABLE\" --probe"
