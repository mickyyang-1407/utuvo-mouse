#!/bin/bash
# MOUSE-008A / R1 — isolated release-input fixture check.
#
# 只用暫存目錄與合成 fixture：驗證 package-release.sh 的 --plan 路徑會拒掉壞輸入、
# 完全不執行任何被提供的執行檔（連 --help／--version 都不行）、完全不碰 Keychain。
#
# 這支腳本不做任何真實發行動作，也不證明任何密碼學成功。
# 相容性：macOS 內建 bash 3.2（不使用 mapfile）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/package-release.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mouse008a-r1.XXXXXX")"

cleanup() {
    case "$TMP" in
        "${TMPDIR:-/tmp}"/mouse008a-r1.*) rm -rf "$TMP" ;;
    esac
}
trap cleanup EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }

FIXTURE_KEY="$(python3 -c 'import base64; print(base64.b64encode(bytes([0x11]*32)).decode())')"
FIXTURE_KEY2="$(python3 -c 'import base64; print(base64.b64encode(bytes([0x22]*32)).decode())')"

# --- 真的 Mach-O stub（arm64 與 universal）----------------------------------
STUB_C="$TMP/stub.c"
printf 'int main(void){return 0;}\n' > "$STUB_C"

make_thin() { # make_thin <out> <arch>
    clang -arch "$2" -o "$1" "$STUB_C" 2>/dev/null
}

make_universal() { # make_universal <out>
    make_thin "$TMP/.thin-arm64" arm64
    make_thin "$TMP/.thin-x86" x86_64
    lipo -create "$TMP/.thin-arm64" "$TMP/.thin-x86" -o "$1"
}

# --- 合成 fixture App -------------------------------------------------------
# 公鑰是合成的 0x11 填充，明確不是任何真實的發行金鑰。
make_app() {
    local app="$1" version="$2" build="$3" key="$4" feed="$5" framework_arch="${6:-universal}"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    make_thin "$app/Contents/MacOS/UTUVO Mouse" arm64
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UTUVO Mouse</string>
    <key>CFBundleIdentifier</key>
    <string>com.utuvo.mouse</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>SUFeedURL</key>
    <string>$feed</string>
    <key>SUPublicEDKey</key>
    <string>$key</string>
</dict>
</plist>
PLIST
    local fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    mkdir -p "$fw/XPCServices/Downloader.xpc/Contents/MacOS" \
             "$fw/XPCServices/Installer.xpc/Contents/MacOS" \
             "$fw/Updater.app/Contents/MacOS"
    local stub
    for stub in "$fw/Sparkle" "$fw/Autoupdate" \
                "$fw/Updater.app/Contents/MacOS/Updater" \
                "$fw/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
                "$fw/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
        if [ "$framework_arch" = "universal" ]; then
            make_universal "$stub"
        else
            make_thin "$stub" arm64
        fi
    done
}

APP="$TMP/fixture/UTUVO Mouse.app"
make_app "$APP" "0.2.0" "3" "$FIXTURE_KEY" "https://example.com/appcast.xml"

# --- 假的敏感工具：證明 plan 路徑完全沒呼叫它們 -------------------------------
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
for fake in security codesign xcrun notarytool stapler spctl ditto; do
    cat > "$FAKEBIN/$fake" <<'FAKE'
#!/bin/sh
echo "CALLED $0" >> "$MOUSE008A_MARKER"
exit 1
FAKE
    chmod +x "$FAKEBIN/$fake"
done
MARKER="$TMP/marker.txt"
export MOUSE008A_MARKER="$MARKER"

# --- 假的「官方版形」Sparkle 工具目錄 ----------------------------------------
# 結構照官方 artifact：<root>/{CHANGELOG,LICENSE,SampleAppcast.xml,Sparkle.xcframework} + <root>/bin/*
make_official_tools() { # make_official_tools <root> <sentinel?>
    local root="$1" sentinel="${2:-}"
    mkdir -p "$root/bin" "$root/Sparkle.xcframework"
    printf '# 2.10.1\n\n* test fixture changelog\n' > "$root/CHANGELOG"
    printf 'fixture license\n' > "$root/LICENSE"
    printf '<?xml version="1.0" encoding="utf-8"?>\n<rss version="2.0"/>\n' > "$root/SampleAppcast.xml"
    cat > "$root/Sparkle.xcframework/Info.plist" <<'XPI'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key><string>macos-arm64_x86_64</string>
            <key>SupportedArchitectures</key>
            <array><string>arm64</string><string>x86_64</string></array>
        </dict>
    </array>
</dict>
</plist>
XPI
    local tool
    for tool in sign_update generate_appcast generate_keys; do
        cat > "$root/bin/$tool" <<'FAKE_TOOL'
#!/bin/bash
# 假的官方工具：任何參數（含 --help／--version）都會留下執行記錄。
echo "CALLED" >> "$MOUSE008A_TOOL_MARKER"
if [ -n "${MOUSE008A_TOOL_STDERR}" ]; then
    echo "fixture tool output"
fi
exit 1
FAKE_TOOL
        chmod +x "$root/bin/$tool"
    done
}

TOOLS="$TMP/sparkle-artifact"
make_official_tools "$TOOLS"
export MOUSE008A_TOOL_MARKER="$TMP/tool-marker.txt"

run_plan() {
    rm -f "$MARKER" "$MOUSE008A_TOOL_MARKER"
    set +e
    PATH="$FAKEBIN:$PATH" "$HELPER" "$@" > "$TMP/out.txt" 2> "$TMP/err.txt"
    local code=$?
    set -e
    echo "$code"
}

BASE_ARGS=(
    --plan
    --app "$APP"
    --output "$TMP/out-valid"
    --version "0.3.0"
    --build "4"
    --identity "Developer ID Application: Fixture Co (ABCDE12345)"
    --notary-profile "fixture-profile"
    --sparkle-account "fixture-account"
    --public-key "$FIXTURE_KEY"
    --download-prefix "https://example.com/releases/download/v0.3.0"
    --project-link "https://example.com/project/utuvo-mouse"
    --sparkle-tools-dir "$TOOLS/bin"
)

VARIANT=()
replace_arg() {
    local key="$1" value="$2"
    local args=()
    local i=0
    local found=0
    while [ $i -lt ${#BASE_ARGS[@]} ]; do
        if [ "${BASE_ARGS[$i]}" = "$key" ]; then
            args+=("$key" "$value")
            found=1
            i=$((i + 2))
        else
            args+=("${BASE_ARGS[$i]}")
            i=$((i + 1))
        fi
    done
    if [ "$found" = "0" ]; then
        args+=("$key" "$value")
    fi
    VARIANT=("${args[@]}")
}

expect_reject() {
    local desc="$1"; shift
    local code
    code="$(run_plan "$@")"
    if [ "$code" = "2" ] && [ ! -f "$MARKER" ]; then
        ok "拒絕：${desc}"
    else
        ng "拒絕：${desc}（結束碼 ${code}）"
        sed -n '1,10p' "$TMP/err.txt"
    fi
}

echo "== MOUSE-008A R1 發行輸入 fixture 檢查 =="

# --- A. R0 既有案例（保留）---------------------------------------------------
code="$(run_plan --help)"
if [ "$code" = "0" ] && [ ! -f "$MARKER" ]; then
    ok "--help 結束碼 0，且未呼叫任何敏感工具"
else
    ng "--help 結束碼 ${code}"
fi

before="$(find "$TMP" -mindepth 1 | sort | md5)"
code="$(run_plan "${BASE_ARGS[@]}")"
after="$(find "$TMP" -mindepth 1 | sort | md5)"
if [ "$code" = "0" ] && [ "$before" = "$after" ] && [ ! -f "$MARKER" ] && [ ! -f "$MOUSE008A_TOOL_MARKER" ]; then
    ok "--plan 通過驗證且零副作用（沒有新增檔案、沒有執行被提供的工具）"
else
    ng "--plan 結束碼 ${code}；前後檔案清單相同=$([ "$before" = "$after" ] && echo 是 || echo 否)；敏感工具 marker=$([ -f "$MARKER" ] && echo 有 || echo 無)；被提供工具 marker=$([ -f "$MOUSE008A_TOOL_MARKER" ] && echo 有 || echo 無)"
    sed -n '1,20p' "$TMP/err.txt"
fi

set +e
PATH="$FAKEBIN:$PATH" "$HELPER" --plan --json "${BASE_ARGS[@]:1}" > "$TMP/plan.json" 2> "$TMP/plan-json-err.txt"
json_code=$?
set -e
if [ "$json_code" = "0" ] && python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
assert data["versions"]["short_version"] == "0.3.0"
assert data["versions"]["build"] == "4"
assert data["output"]["created"] is False
assert data["signing"]["team_id"] == "ABCDE12345"
assert "Fixture Co" not in json.dumps(data)
' "$TMP/plan.json"; then
    ok "--plan --json 輸出可解析，且已遮蔽個人憑證標籤"
else
    ng "--plan --json 結束碼 ${json_code} 或內容不符"
    sed -n '1,20p' "$TMP/plan-json-err.txt"
fi

replace_arg --public-key "not-base64!!"
expect_reject "公鑰不是合法 base64" "${VARIANT[@]}"

short_key="$(python3 -c 'import base64; print(base64.b64encode(bytes(16)).decode())')"
replace_arg --public-key "$short_key"
expect_reject "公鑰解碼後不是 32 位元組" "${VARIANT[@]}"

zero_key="$(python3 -c 'import base64; print(base64.b64encode(bytes(32)).decode())')"
replace_arg --public-key "$zero_key"
expect_reject "全零佔位公鑰" "${VARIANT[@]}"

replace_arg --public-key "$FIXTURE_KEY2"
expect_reject "公鑰與 App 內嵌值不一致" "${VARIANT[@]}"

replace_arg --public-key ""
expect_reject "缺少公鑰" "${VARIANT[@]}"

replace_arg --download-prefix "http://example.com/x"
expect_reject "下載前綴不是 https" "${VARIANT[@]}"

replace_arg --download-prefix "https:///appcast.xml"
expect_reject "下載前綴沒有主機名稱" "${VARIANT[@]}"

replace_arg --project-link "https://localhost/project"
expect_reject "專案連結主機名稱不是公開網域" "${VARIANT[@]}"

replace_arg --build "0"
expect_reject "build 是 0" "${VARIANT[@]}"

replace_arg --build "-3"
expect_reject "build 是負數" "${VARIANT[@]}"

replace_arg --build "abc"
expect_reject "build 不是整數" "${VARIANT[@]}"

replace_arg --build "3"
expect_reject "build 沒有比目前 build 大（monotonic）" "${VARIANT[@]}"

replace_arg --version "0.1.0"
expect_reject "版本沒有比目前版本大" "${VARIANT[@]}"

replace_arg --output "$APP/Contents/staging"
expect_reject "輸出目錄在輸入 App 內部" "${VARIANT[@]}"

replace_arg --output "$TMP/fixture"
expect_reject "輸出目錄是輸入 App 的上層" "${VARIANT[@]}"

mkdir -p "$TMP/existing-out"
replace_arg --output "$TMP/existing-out"
expect_reject "輸出目錄已存在" "${VARIANT[@]}"

replace_arg --sparkle-account ""
expect_reject "缺少 Sparkle 帳號" "${VARIANT[@]}"

replace_arg --identity ""
expect_reject "缺少簽章身分" "${VARIANT[@]}"

replace_arg --notary-profile ""
expect_reject "缺少 notary profile" "${VARIANT[@]}"

replace_arg --identity "Mac Developer: Someone (ABCDE12345)"
expect_reject "身分不是 Developer ID Application" "${VARIANT[@]}"

replace_arg --feed-url "ftp://example.com/appcast.xml"
expect_reject "feed URL 不是 https" "${VARIANT[@]}"

APP_NO_KEY="$TMP/fixture-no-key/UTUVO Mouse.app"
make_app "$APP_NO_KEY" "0.2.0" "3" "" "https://example.com/appcast.xml"
replace_arg --app "$APP_NO_KEY"
expect_reject "App 沒有內嵌公鑰" "${VARIANT[@]}"

APP_OTHER_ID="$TMP/fixture-other-id/UTUVO Mouse.app"
make_app "$APP_OTHER_ID" "0.2.0" "3" "$FIXTURE_KEY" "https://example.com/appcast.xml"
python3 - "$APP_OTHER_ID/Contents/Info.plist" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read().replace("com.utuvo.mouse", "com.example.other")
open(path, "w").write(text)
PY
replace_arg --app "$APP_OTHER_ID"
expect_reject "bundle id 不是 com.utuvo.mouse" "${VARIANT[@]}"

# --- B. R1 針對性新案例（對應 6 項審查發現）----------------------------------
echo "-- B. R1 針對性案例"

# B1（P1）plan 絕對不能執行被提供的執行檔（連 --help／--version 都不行）
code="$(run_plan "${BASE_ARGS[@]}")"
if [ "$code" = "0" ] && [ ! -f "$MOUSE008A_TOOL_MARKER" ]; then
    ok "plan 沒有執行被提供的 Sparkle 工具（sentinel 無記錄）"
else
    ng "plan 執行了被提供的工具（結束碼 ${code}）"
fi

# B2（P1）版本來源改為靜態 artifact 中繼資料，不靠工具輸出
B2TOOLS="$TMP/sparkle-artifact-static"
make_official_tools "$B2TOOLS"
printf '# 2.10.1\n\n* fixture\n' > "$B2TOOLS/CHANGELOG"
replace_arg --sparkle-tools-dir "$B2TOOLS/bin"
code="$(run_plan "${VARIANT[@]}")"
if [ "$code" = "0" ] && [ ! -f "$MOUSE008A_TOOL_MARKER" ]; then
    ok "plan 用靜態 CHANGELOG 驗證釘住版本，不依賴工具的 --version/--help"
else
    ng "plan 無法用靜態中繼資料確認版本（結束碼 ${code}）"
    sed -n '1,10p' "$TMP/err.txt"
fi
replace_arg --sparkle-tools-dir "$TOOLS/bin"

# B3（P2）架構讀不到 → fail closed
BADARCH="$TMP/fixture-badarch/UTUVO Mouse.app"
make_app "$BADARCH" "0.2.0" "3" "$FIXTURE_KEY" "https://example.com/appcast.xml"
printf 'not a mach-o\n' > "$BADARCH/Contents/MacOS/UTUVO Mouse"
replace_arg --app "$BADARCH"
expect_reject "主執行檔架構讀不到（必須 fail closed）" "${VARIANT[@]}"
replace_arg --app "$APP"

# B4（P2）universal 框架（arm64 + x86_64）不得被誤判拒絕
UNIV="$TMP/fixture-universal/UTUVO Mouse.app"
make_app "$UNIV" "0.2.0" "3" "$FIXTURE_KEY" "https://example.com/appcast.xml" universal
replace_arg --app "$UNIV"
code="$(run_plan "${VARIANT[@]}")"
if [ "$code" = "0" ]; then
    ok "universal Sparkle.framework（arm64+x86_64）不被拒絕"
else
    ng "universal Sparkle.framework 被誤拒（結束碼 ${code}）"
    sed -n '1,10p' "$TMP/err.txt"
fi
replace_arg --app "$APP"

# B5（P1）不得使用文件記載的預設帳號 ed25519
replace_arg --sparkle-account "ed25519"
expect_reject "Sparkle 帳號是文件記載的預設值 ed25519" "${VARIANT[@]}"
replace_arg --sparkle-account "fixture-account"

# B6（P2）--i-have-authorization 已移除
set +e
"$HELPER" --plan --i-have-authorization "${BASE_ARGS[@]:1}" > "$TMP/gate.txt" 2>&1
gate_code=$?
set -e
if [ "$gate_code" != "0" ] && grep -q "未知選項" "$TMP/gate.txt"; then
    ok "--i-have-authorization 已移除（不再有額外授權閘門）"
else
    ng "--i-have-authorization 仍然存在（結束碼 ${gate_code}）"
fi

# --- C. mock 執行流程（工具全是假的，不構成任何簽章／公证證據）---------------
echo "-- C. mock 執行流程（工具全假）"

MOCKBIN="$TMP/mockbin"
MOCKTOOLS="$TMP/mock-artifact"
mkdir -p "$MOCKBIN"
make_official_tools "$MOCKTOOLS"

cat > "$MOCKBIN/codesign" <<'FAKE_CODESIGN'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        -dv|-d)
            echo "Identifier=com.utuvo.mouse"
            echo "Authority=Developer ID Application: PLACEHOLDER (ABCDE12345)"
            echo "TeamIdentifier=ABCDE12345"
            if [ "$1" = "-d" ]; then
                echo "designated = and/or identifier \"com.utuvo.mouse\""
            fi
            exit 0
            ;;
    esac
done
exit 0
FAKE_CODESIGN

# 真的 notarytool 沒有 --output-file：假的 xcrun 直接拒絕這個選項。
cat > "$MOCKBIN/xcrun" <<'FAKE_XCRUN'
#!/bin/bash
for arg in "$@"; do
    if [ "$arg" = "--output-file" ]; then
        echo "unknown option --output-file" >&2
        exit 64
    fi
done
if [ "$1" = "notarytool" ]; then
    shift
    if [ "$1" = "submit" ]; then
        echo '{"status":"Accepted","id":"MOCK-NOT-REAL"}'
        exit 0
    fi
fi
exit 0
FAKE_XCRUN

cat > "$MOCKBIN/spctl" <<'FAKE_SPCTL'
#!/bin/bash
exit 0
FAKE_SPCTL

cat > "$MOCKBIN/security" <<'FAKE_SECURITY'
#!/bin/sh
echo "CALLED security" >> "$MOUSE008A_MARKER"
exit 1
FAKE_SECURITY

chmod +x "$MOCKBIN/codesign" "$MOCKBIN/xcrun" "$MOCKBIN/spctl" "$MOCKBIN/security"

# 假的 sign_update：會把每一次呼叫的參數記錄下來，供檢查 --account 有沒有帶。
cat > "$MOCKTOOLS/bin/sign_update" <<'FAKE_SIGN'
#!/bin/bash
echo "ARGS $*" >> "$MOUSE008A_SIGN_LOG"
if [ "$1" = "--help" ]; then
    echo "usage: sign_update [--account <account>] [--verify] [-p] <file-path> [<verify-signature>]"
    exit 0
fi
if [ "$1" = "--verify" ]; then
    exit 0
fi
python3 -c 'import base64; print(base64.b64encode(bytes([0x33]*64)).decode())'
FAKE_SIGN
chmod +x "$MOCKTOOLS/bin/sign_update"

# 假的 generate_keys：只做公開金鑰查詢（-p），輸出指定的金鑰。
cat > "$MOCKTOOLS/bin/generate_keys" <<'FAKE_KEYS'
#!/bin/bash
echo "ARGS $*" >> "$MOUSE008A_KEYS_LOG"
if [ "$1" = "--help" ]; then
    echo "usage: generate_keys [--account <account>] [-p]"
    exit 0
fi
if [ "$1" = "--account" ] && [ "$3" = "-p" ]; then
    printf '%s\n' "$MOCK_PUBLIC_KEY"
    exit 0
fi
exit 1
FAKE_KEYS
chmod +x "$MOCKTOOLS/bin/generate_keys"

# 假的 generate_appcast：產生「真實格式」的 appcast（前置命名空間 + 子元素版本號）。
cat > "$MOCKTOOLS/bin/generate_appcast" <<'FAKE_APPCAST'
#!/bin/bash
if [ "$1" = "--help" ]; then
    echo "usage: generate_appcast [--account <account>] [--download-url-prefix <url>] [--link <link>] [--maximum-deltas <n>] <dir>"
    exit 0
fi
prefix=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "--download-url-prefix" ]; then
        prefix="$arg"
    fi
    prev="$arg"
done
dir=""
for arg in "$@"; do
    dir="$arg"
done
zip="$(ls "$dir"/*.zip | head -1)"
size="$(stat -f%z "$zip")"
name="$(basename "$zip")"
# Match the official generator: a prefix without trailing slash replaces its last path component.
resolved_url="$(python3 -c 'import sys; from urllib.parse import urljoin; print(urljoin(sys.argv[1], sys.argv[2]))' "$prefix" "$name")"
plist="$(mktemp)"
unzip -p "$zip" 'UTUVO Mouse.app/Contents/Info.plist' > "$plist"
ver="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")"
build="$(plutil -extract CFBundleVersion raw -o - "$plist")"
sig="$(python3 -c 'import base64; print(base64.b64encode(bytes([0x33]*64)).decode())')"
cat > "$dir/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Fixture Appcast</title>
        <item>
            <title>Version $ver</title>
            <link>https://example.com/project/utuvo-mouse</link>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$ver</sparkle:shortVersionString>
            <pubDate>Wed, 01 Jan 2025 00:00:00 +0000</pubDate>
            <enclosure url="$resolved_url" length="$size" type="application/octet-stream" sparkle:edSignature="$sig" />
        </item>
    </channel>
</rss>
XML
exit 0
FAKE_APPCAST
chmod +x "$MOCKTOOLS/bin/generate_appcast"

export MOUSE008A_SIGN_LOG="$TMP/sign-args.log"
export MOUSE008A_KEYS_LOG="$TMP/keys-args.log"
export MOCK_PUBLIC_KEY="$FIXTURE_KEY"

FPRINT="$(python3 -c "import base64,hashlib; print(hashlib.sha256(base64.b64decode('$FIXTURE_KEY')).hexdigest())")"

run_mock_execute() { # run_mock_execute <output-dir> <feed-url>
    rm -f "$MARKER" "$MOUSE008A_SIGN_LOG" "$MOUSE008A_KEYS_LOG"
    set +e
    PATH="$MOCKBIN:$PATH" "$HELPER" --execute \
        --app "$APP" --output "$1" --version "0.3.0" --build "4" \
        --identity "Developer ID Application: PLACEHOLDER (ABCDE12345)" \
        --notary-profile "PLACEHOLDER" --sparkle-account "fixture-account" \
        --public-key "$FIXTURE_KEY" --public-key-fingerprint "$FPRINT" \
        --download-prefix "https://example.com/releases/download/v0.3.0" \
        --project-link "https://example.com/project/utuvo-mouse" \
        --sparkle-tools-dir "$MOCKTOOLS/bin" \
        ${2:+--feed-url "$2"} > "$TMP/mock-exec.log" 2>&1
    local code=$?
    set -e
    echo "$code"
}

code="$(run_mock_execute "$TMP/mock-out" "")"
if [ "$code" = "0" ] && [ ! -f "$MARKER" ]; then
    ok "mock 執行流程跑完（沒有呼叫 security／Keychain）"
else
    ng "mock 執行流程失敗（結束碼 ${code}）"
    tail -20 "$TMP/mock-exec.log"
fi

if grep -q -- "--output-file" "$TMP/mock-exec.log"; then
    ng "使用了 notarytool 不支援的 --output-file"
else
    ok "notarytool 呼叫沒有使用不支援的 --output-file"
fi

if grep -q -- "--account fixture-account --verify" "$MOUSE008A_SIGN_LOG" 2>/dev/null || \
   grep -q -- "--verify .* --account fixture-account" "$MOUSE008A_SIGN_LOG" 2>/dev/null; then
    ok "sign_update --verify 有帶同一個 --account"
else
    ng "sign_update --verify 沒有帶 --account"
    sed -n '1,10p' "$MOUSE008A_SIGN_LOG" 2>/dev/null
fi

if grep -q -- "--account fixture-account -p" "$MOUSE008A_KEYS_LOG" 2>/dev/null; then
    ok "generate_keys 以 --account ACCOUNT -p 查詢公開金鑰（不產生金鑰）"
else
    ng "generate_keys 沒有用 --account ACCOUNT -p 查詢"
    sed -n '1,10p' "$MOUSE008A_KEYS_LOG" 2>/dev/null
fi

PUBLISH="$TMP/mock-out/publish"
publish_files="$(ls -1 "$PUBLISH" 2>/dev/null | sort | tr '\n' ' ')"
if [ "$publish_files" = "SHA256SUMS UTUVO-Mouse-0.3.0-4.zip appcast.xml " ]; then
    ok "發布目錄只有三個檔案（正式 ZIP、appcast.xml、SHA256SUMS）"
else
    ng "發布目錄內容不符：${publish_files}"
fi

if [ -f "$TMP/mock-out/staging/pre-notary-0.3.0-4.zip" ]; then
    ok "私有暫存留在 staging（pre-notary ZIP 不在發布目錄）"
else
    ng "staging 內容不符"
fi

# 真實格式的 appcast（前置命名空間、版本是子元素）必須能被解析
if python3 - "$PUBLISH/appcast.xml" "0.3.0" "4" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(path).getroot()
items = root.findall("./channel/item")
assert len(items) == 1, items
item = items[0]
assert item.find(NS + "version").text == build
assert item.find(NS + "shortVersionString").text == version
enclosure = item.find("enclosure")
assert enclosure.get("url")
assert enclosure.get("length")
assert enclosure.get(NS + "edSignature")
PY
then
    ok "appcast 可被真實格式解析（前置命名空間、版本為子元素）"
else
    ng "appcast 真實格式解析失敗"
fi

# 帳號公開金鑰與 App 內嵌金鑰不符 → 必須拒絕
MOCK_PUBLIC_KEY="$FIXTURE_KEY2" code="$(run_mock_execute "$TMP/mock-out-keymismatch" "")"
if [ "$code" != "0" ]; then
    ok "帳號公開金鑰與 App 內嵌金鑰不符時拒絕發行"
else
    ng "金鑰不符竟然放行"
fi
export MOCK_PUBLIC_KEY="$FIXTURE_KEY"

# --feed-url 必須真的寫進暫存 App 的 Info.plist
FEED="https://example.com/feed/appcast.xml"
code="$(run_mock_execute "$TMP/mock-out-feed" "$FEED")"
if [ "$code" = "0" ] && \
   [ "$(plutil -extract SUFeedURL raw -o - "$TMP/mock-out-feed/staging/app/UTUVO Mouse.app/Contents/Info.plist")" = "$FEED" ]; then
    ok "--feed-url 有套用到暫存 App 的 SUFeedURL"
else
    ng "--feed-url 沒有套用到暫存 App（結束碼 ${code}）"
fi

# Sparkle 工具缺必要旗標時必須 fail-closed
cat > "$MOCKTOOLS/bin/generate_appcast" <<'FAKE_APPCAST_NOFLAG'
#!/bin/bash
if [ "$1" = "--help" ]; then
    echo "usage: generate_appcast [--account <account>] <dir>"
    exit 0
fi
exit 0
FAKE_APPCAST_NOFLAG
chmod +x "$MOCKTOOLS/bin/generate_appcast"
code="$(run_mock_execute "$TMP/mock-out-noflag" "")"
if [ "$code" != "0" ]; then
    ok "Sparkle 工具缺必要旗標時 fail-closed（不猜旗標、不硬跑）"
else
    ng "缺旗標時沒有正確拒絕（結束碼 ${code}）"
fi

if [ -n "${MOUSE008A_KEEP_DIR:-}" ] && [ -d "${MOUSE008A_KEEP_DIR}" ]; then
    for keep in mock-exec.log sign-args.log keys-args.log; do
        if [ -f "$TMP/$keep" ]; then
            cp "$TMP/$keep" "${MOUSE008A_KEEP_DIR}/C-$keep"
        fi
    done
fi

echo "== 結果：PASS ${PASS}、FAIL ${FAIL} =="
[ "$FAIL" = "0" ] || exit 1
