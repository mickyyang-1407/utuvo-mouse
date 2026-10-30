#!/bin/bash
# UTUVO Mouse — reproducible secure release helper (MOUSE-008A)
#
# Every credential-like input is an explicit argument. This script never
# discovers, creates, exports, imports or stores a credential, never touches
# the Keychain, never generates an update key, never accepts a private key
# through argv/env/file and never performs an upload.
#
# Modes:
#   --plan     validate the inputs and print the plan. No side effects at all:
#              no file is created, no directory is touched, no app is executed,
#              no code is signed, nothing is sent over the network.
#   --execute  the real release (Root only, after the UI/device gates).
#
# The ticket writer only ever runs `--help` and `--plan` against temporary
# fixtures. Real signing / notarisation / stapling / appcast publication is
# Root's job and needs the concrete gates in docs/RELEASING.md.
set -euo pipefail

BUNDLE_ID_EXPECTED="com.utuvo.mouse"
APP_NAME_EXPECTED="UTUVO Mouse"

MODE=""
APP=""
OUT=""
VER=""
BUILD=""
IDENT=""
PROFILE=""
ACCOUNT=""
PUBKEY=""
KEY_FPRINT=""
DL_PREFIX=""
PROJ_LINK=""
FEED_OVERRIDE=""
TOOLS_DIR=""
EXPECTED_SPARKLE="2.10.1"
JSON_OUT=0
WANT_HELP=0

usage() {
    cat <<'USAGE'
UTUVO Mouse 發行輔助工具（MOUSE-008A）

用法：
  package-release.sh --plan    [選項]   # 只驗證輸入並輸出計畫，零副作用
  package-release.sh --execute [選項]   # 真正發行（僅限 Root；--execute 本身就是明確動作）
  package-release.sh --help              # 本說明（無副作用）

必要輸入（全部要明講，不做自動搜尋）：
  --app PATH               已建置好的 .app（不可是符號連結）
  --output DIR             新的輸出目錄（不可已存在；助手不會覆寫）
  --version X.Y[.Z]        CFBundleShortVersionString
  --build N                CFBundleVersion，必須是正整數且大於目前 build
  --identity NAME          明確的 Developer ID Application 身分
  --notary-profile NAME    已存在的 notarytool keychain profile 名稱
  --sparkle-account NAME   Sparkle 更新金鑰帳號（明確指定，不吃預設全域帳號）
  --public-key BASE64      Ed25519 公鑰（base64，剛好 32 位元組）
  --download-prefix URL    https 開頭的下載前綴（要有真實主機名稱）
  --project-link URL       https 開頭的專案連結（要有真實主機名稱）

選用輸入：
  --feed-url URL           覆寫 appcast feed URL（--execute 會套用到暫存 App 的 SUFeedURL）
  --sparkle-tools-dir DIR  官方 Sparkle artifact 的 bin 目錄（sign_update、generate_appcast、generate_keys）
  --expected-sparkle-version V  釘住的 Sparkle 版本（預設 2.10.1），比對官方 CHANGELOG
  --public-key-fingerprint HEX  公鑰 SHA-256 指紋；--execute 必填，避免佔位金鑰被當成發行金鑰
  --json                   以 JSON 輸出計畫資料（僅 --plan）

本工具不會做的事：
  * 不建立、不匯出、不匯入任何金鑰或憑證；不讀寫 Keychain
  * 不產生、不安裝、不撤銷憑證或 notary profile
  * 不接受任何私鑰（argv／環境變數／檔案都拒絕）
  * 不做任何上傳、git、GitHub、發行頁面動作
  * 不登錄、不改登入項目、不動 TCC、不結束任何 App 或服務
  * 不使用 codesign --deep 簽章；--deep 只用於驗證
USAGE
}

die() {
    echo "錯誤：$*" >&2
    exit 1
}

need_value() {
    # 選項缺少值時給清楚錯誤，不要讓 shift 自己爆掉。
    [ "$2" -ge 2 ] || die "$1 需要一個值。"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) WANT_HELP=1; shift ;;
        --plan) MODE="plan"; shift ;;
        --execute) MODE="execute"; shift ;;
        --app) need_value "$1" $#; APP="${2:-}"; shift 2 ;;
        --output) need_value "$1" $#; OUT="${2:-}"; shift 2 ;;
        --version) need_value "$1" $#; VER="${2:-}"; shift 2 ;;
        --build) need_value "$1" $#; BUILD="${2:-}"; shift 2 ;;
        --identity) need_value "$1" $#; IDENT="${2:-}"; shift 2 ;;
        --notary-profile) need_value "$1" $#; PROFILE="${2:-}"; shift 2 ;;
        --sparkle-account) need_value "$1" $#; ACCOUNT="${2:-}"; shift 2 ;;
        --public-key) need_value "$1" $#; PUBKEY="${2:-}"; shift 2 ;;
        --public-key-fingerprint) need_value "$1" $#; KEY_FPRINT="${2:-}"; shift 2 ;;
        --download-prefix) need_value "$1" $#; DL_PREFIX="${2:-}"; shift 2 ;;
        --project-link) need_value "$1" $#; PROJ_LINK="${2:-}"; shift 2 ;;
        --feed-url) need_value "$1" $#; FEED_OVERRIDE="${2:-}"; shift 2 ;;
        --sparkle-tools-dir) need_value "$1" $#; TOOLS_DIR="${2:-}"; shift 2 ;;
        --expected-sparkle-version) need_value "$1" $#; EXPECTED_SPARKLE="${2:-}"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        *) die "未知選項：${1}（用 --help 看用法）" ;;
    esac
done

if [ "$WANT_HELP" = "1" ]; then
    usage
    exit 0
fi

if [ -z "$MODE" ]; then
    die "請指定 --plan 或 --execute（或 --help）。"
fi

if [ "$MODE" = "execute" ]; then
    # 任何私鑰都不准從環境進來。簽章金鑰只能留在 Keychain，由 Sparkle 工具自己取用。
    unset SPARKLE_PRIVATE_KEY SPARKLE_PRIVATE_KEY_FILE SPARKLE_ED_PRIVATE_KEY || true
fi

# ---------------------------------------------------------------------------
# 輸入驗證（純讀取，無副作用）
# ---------------------------------------------------------------------------
validate_inputs() {
    python3 - "$@" <<'PY'
import base64
import hashlib
import os
import plistlib
import re
import subprocess
import sys

(mode, app, out, ver, build, ident, profile, account, pubkey,
 fprint, dlp, link, feed_override, tools, want_json,
 expected_sparkle) = sys.argv[1:17]

errs = []
notes = []
data = {}


def err(msg):
    errs.append(msg)


def note(msg):
    notes.append(msg)


def https_url_ok(value, label):
    value = (value or "").strip()
    if not value:
        err("%s 不可為空" % label)
        return False
    try:
        from urllib.parse import urlparse
        parsed = urlparse(value)
    except ValueError:
        err("%s 不是合法 URL：%s" % (label, value))
        return False
    if parsed.scheme != "https":
        err("%s 必須使用 https：%s" % (label, value))
        return False
    if not parsed.netloc or not parsed.hostname:
        err("%s 缺少主機名稱：%s" % (label, value))
        return False
    if parsed.username or parsed.password:
        err("%s 不可內含帳密" % label)
        return False
    host = parsed.hostname
    if "." not in host:
        err("%s 的主機名稱不像公開網域（需要至少一個句點）：%s" % (label, host))
        return False
    if not re.match(r"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$", host):
        err("%s 的主機名稱格式不合法：%s" % (label, host))
        return False
    return True


def lipo_archs(path):
    if not path or not os.path.isfile(path):
        return None
    try:
        proc = subprocess.run(["lipo", "-archs", path],
                              capture_output=True, text=True, timeout=60)
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    return sorted({a.strip() for a in proc.stdout.split() if a.strip()})


def file_sha256(path):
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError:
        return ""
    return digest.hexdigest()


def read_changelog_version(path):
    # 官方 artifact 的 CHANGELOG 第一個標題就是版本（例如 "# 2.10.1"）。
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for _ in range(40):
                line = handle.readline()
                if not line:
                    break
                match = re.match(r"^#\s+v?(\d+(?:\.\d+)+)\s*$", line.strip())
                if match:
                    return match.group(1)
    except OSError:
        return ""
    return ""


def read_xcframework_archs(path):
    try:
        with open(path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception:
        return []
    archs = []
    for library in plist.get("AvailableLibraries", []) or []:
        for arch in library.get("SupportedArchitectures", []) or []:
            if arch not in archs:
                archs.append(arch)
    return sorted(archs)


# --- 輸入 App ---------------------------------------------------------------
app_path = os.path.abspath(app) if app else ""
info = {}
if not app:
    err("--app 必填（明確的 .app 路徑，不做自動搜尋）")
elif os.path.islink(app_path):
    err("--app 不可是符號連結：%s" % app_path)
elif not os.path.exists(app_path):
    err("--app 不存在：%s" % app_path)
elif not os.path.isdir(app_path):
    err("--app 必須是目錄形式的 .app：%s" % app_path)
elif not app_path.endswith(".app"):
    err("--app 必須以 .app 結尾：%s" % app_path)

data["app_path"] = app_path

if app_path and os.path.isdir(app_path) and not os.path.islink(app_path):
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    if not os.path.isfile(plist_path):
        err("App 內沒有 Contents/Info.plist：%s" % plist_path)
    else:
        try:
            with open(plist_path, "rb") as handle:
                plist = plistlib.load(handle)
        except Exception as exc:
            plist = {}
            err("Info.plist 無法解析：%s" % exc)
        info["bundle_id"] = str(plist.get("CFBundleIdentifier", ""))
        if info["bundle_id"] != "com.utuvo.mouse":
            err("bundle id 必須維持 com.utuvo.mouse，實際為 %r" % info["bundle_id"])
        info["current_version"] = str(plist.get("CFBundleShortVersionString", ""))
        info["current_build"] = str(plist.get("CFBundleVersion", ""))
        info["app_public_key"] = str(plist.get("SUPublicEDKey", "")).strip()
        info["app_feed"] = str(plist.get("SUFeedURL", "")).strip()
        info["min_os"] = str(plist.get("LSMinimumSystemVersion", ""))
        exe = str(plist.get("CFBundleExecutable", ""))
        if exe and os.path.basename(exe) != exe:
            err("CFBundleExecutable 不可包含路徑分隔符：%r" % exe)
            exe = ""
        info["executable"] = os.path.join(app_path, "Contents", "MacOS", exe) if exe else ""
        if exe and not os.path.isfile(info["executable"]):
            err("找不到主執行檔：%s" % info["executable"])

    # macOS 14 目標
    min_os = info.get("min_os", "")
    match = re.match(r"^(\d+)(?:\.(\d+))?", min_os)
    if not match:
        err("LSMinimumSystemVersion 缺失或格式不明：%r" % min_os)
    elif int(match.group(1)) < 14:
        err("LSMinimumSystemVersion 必須是 macOS 14 以上，實際 %r" % min_os)

    # 架構 fail closed：讀不到就不能放行。
    archs = lipo_archs(info.get("executable", ""))
    info["archs"] = archs
    if archs is None:
        err("讀不到主執行檔架構（lipo 無法解析），必須 fail closed：%s"
            % info.get("executable", ""))
    elif archs != ["arm64"]:
        err("App 必須剛好是 arm64，實際架構：%s" % ",".join(archs))

    # Sparkle.framework 與它的 helper 可以是 universal（arm64 + x86_64），
    # 但一定要含 arm64；讀不到同樣 fail closed。
    framework_root = os.path.join(app_path, "Contents", "Frameworks",
                                  "Sparkle.framework", "Versions", "B")
    framework_items = [
        ("Sparkle.framework", os.path.join(framework_root, "Sparkle")),
        ("Autoupdate", os.path.join(framework_root, "Autoupdate")),
        ("Updater", os.path.join(framework_root, "Updater.app", "Contents", "MacOS", "Updater")),
        ("Downloader.xpc", os.path.join(framework_root, "XPCServices", "Downloader.xpc",
                                        "Contents", "MacOS", "Downloader")),
        ("Installer.xpc", os.path.join(framework_root, "XPCServices", "Installer.xpc",
                                       "Contents", "MacOS", "Installer")),
    ]
    info["framework_archs"] = {}
    for label, path in framework_items:
        item_archs = lipo_archs(path)
        info["framework_archs"][label] = item_archs
        if item_archs is None:
            err("讀不到 %s 的架構（必須 fail closed）：%s" % (label, path))
        elif "arm64" not in item_archs:
            err("%s 必須含 arm64，實際：%s" % (label, ",".join(item_archs)))

# --- 版本與 build ----------------------------------------------------------
if not ver or not re.match(r"^\d+\.\d+(\.\d+)?$", ver):
    err("--version 格式錯誤（需 x.y 或 x.y.z）：%r" % ver)
if not build or not re.match(r"^\d+$", build):
    err("--build 必須是正整數：%r" % build)
else:
    build_value = int(build)
    if build_value < 1:
        err("--build 必須 ≥ 1")
    current_build = info.get("current_build", "")
    if current_build.isdigit() and build_value <= int(current_build):
        err("--build 必須大於目前 build（monotonic）：目前 %s，新的 %s"
            % (current_build, build))
    current_version = info.get("current_version", "")
    if current_version and ver:
        def as_tuple(text):
            return tuple(int(part) for part in text.split(".") if part.isdigit())
        if as_tuple(ver) <= as_tuple(current_version):
            err("--version 必須大於目前版本：目前 %s，新的 %s" % (current_version, ver))

# --- 憑證名稱（只接受名字，不接受任何秘密）--------------------------------
if not ident or not ident.strip():
    err("--identity 必填（明確的 Developer ID Application 身分，不做自動搜尋）")
else:
    match = re.search(r"\(([A-Z0-9]{10})\)", ident)
    info["team_id"] = match.group(1) if match else ""
    if "Developer ID Application" not in ident:
        err("--identity 必須是 'Developer ID Application' 身分：%s" % ident)
    if not match:
        note("identity 沒帶 (TEAMID)，發行時會再檢查 team id 非空")

if not profile or not profile.strip():
    err("--notary-profile 必填（明確指定已存在的 profile 名稱）")
elif profile.strip().startswith("-"):
    err("--notary-profile 不可用 - 開頭")

if not account or not account.strip():
    err("--sparkle-account 必填（不可使用預設或全域帳號）")
elif account.strip().lower() in ("default", "global", "sparkle", "none", "ed25519"):
    err("--sparkle-account 不可使用文件記載的預設／全域帳號（ed25519 是官方預設）：%s"
        % account)

# --- 更新公鑰 --------------------------------------------------------------
key_bytes = None
if not pubkey or not pubkey.strip():
    err("--public-key 必填（Ed25519 公鑰，base64 編碼的 32 位元組）")
else:
    try:
        key_bytes = base64.b64decode(pubkey.strip(), validate=True)
    except Exception:
        err("--public-key 不是合法的 base64")
    if key_bytes is not None:
        if len(key_bytes) != 32:
            err("--public-key 解碼後必須剛好 32 位元組，實際 %d" % len(key_bytes))
        else:
            if key_bytes == b"\x00" * 32:
                err("--public-key 是全零佔位金鑰，不可當成發行金鑰")
            elif key_bytes[:1] == b"\x01" and key_bytes[1:] == b"\x00" * 31:
                err("--public-key 是 Ed25519 單位元佔位金鑰，不可當成發行金鑰")
            fingerprint = hashlib.sha256(key_bytes).hexdigest()
            info["key_fingerprint"] = fingerprint
            if fprint and fprint.strip().lower() != fingerprint:
                err("--public-key-fingerprint 與實際公鑰不符")
            if mode == "execute" and not fprint.strip():
                err("發行模式必須提供 --public-key-fingerprint（避免佔位金鑰被當成發行金鑰）")
            app_key = info.get("app_public_key", "")
            if not app_key:
                err("App 內嵌的 SUPublicEDKey 是空的：這個 App 還沒設定更新金鑰，不可發行")
            elif app_key != pubkey.strip():
                err("--public-key 與 App 內嵌的 SUPublicEDKey 不一致")

# --- 網址 ------------------------------------------------------------------
https_url_ok(dlp, "--download-prefix")
https_url_ok(link, "--project-link")
feed = feed_override.strip() if feed_override else info.get("app_feed", "")
if not feed_override and not feed:
    err("App 內嵌的 SUFeedURL 是空的：請用 --feed-url 指定")
https_url_ok(feed, "appcast feed")
info["feed_url"] = feed

# --- Sparkle 官方工具（只讀靜態中繼資料；plan 絕不執行任何被提供的檔案）-----
info["tools_dir"] = os.path.abspath(tools) if tools else ""
info["tools_verified"] = {}
if tools:
    tools_abs = os.path.abspath(tools)
    if not os.path.isdir(tools_abs):
        err("--sparkle-tools-dir 不存在：%s" % tools_abs)
    else:
        for tool_name in ("sign_update", "generate_appcast", "generate_keys"):
            tool_path = os.path.join(tools_abs, tool_name)
            if not os.path.isfile(tool_path) or not os.access(tool_path, os.X_OK):
                err("缺少可執行檔：%s" % tool_path)
            else:
                info["tools_verified"][tool_name] = file_sha256(tool_path)
        artifact_root = os.path.dirname(tools_abs)
        info["artifact_root"] = artifact_root
        changelog = os.path.join(artifact_root, "CHANGELOG")
        info["artifact_changelog"] = changelog
        if not os.path.isfile(changelog):
            err("官方 artifact 版形不完整：缺少 %s" % changelog)
        else:
            version = read_changelog_version(changelog)
            info["artifact_version"] = version
            if not version:
                err("無法從 %s 讀出 Sparkle 版本" % changelog)
            elif version != expected_sparkle:
                err("釘住版本不符：官方 artifact 是 %s，預期 %s"
                    % (version, expected_sparkle))
        xcframework_plist = os.path.join(artifact_root, "Sparkle.xcframework",
                                         "Info.plist")
        if not os.path.isfile(xcframework_plist):
            err("官方 artifact 版形不完整：缺少 %s" % xcframework_plist)
        else:
            framework_archs = read_xcframework_archs(xcframework_plist)
            info["artifact_framework_archs"] = framework_archs
            if framework_archs and "arm64" not in framework_archs:
                err("官方 Sparkle.framework 不含 arm64：%s" % ",".join(framework_archs))
        info["artifact_sample_appcast"] = os.path.exists(
            os.path.join(artifact_root, "SampleAppcast.xml"))
else:
    if mode == "execute":
        err("--sparkle-tools-dir 必填（要指向官方 Sparkle artifact 的 bin 目錄）")
    else:
        note("未提供 --sparkle-tools-dir（發行時必須指向官方 Sparkle artifact 的 bin 目錄）")

# --- 輸出目錄 --------------------------------------------------------------
output_path = os.path.abspath(out) if out else ""
data["output_path"] = output_path
if not out:
    err("--output 必填（新的輸出目錄）")
else:
    if output_path in ("/", os.path.expanduser("~")):
        err("--output 不可是根目錄或家目錄")
    if len([p for p in output_path.split(os.sep) if p]) < 2:
        err("--output 路徑層級太淺，容易誤刪：%s" % output_path)
    if os.path.islink(output_path):
        err("--output 不可是符號連結：%s" % output_path)
    if os.path.exists(output_path):
        err("--output 已存在，助手不會覆寫既有目錄：%s" % output_path)
    else:
        parent = os.path.dirname(output_path)
        if not os.path.isdir(parent):
            err("--output 的上層目錄不存在：%s" % parent)
    if app_path:
        real_app = os.path.realpath(app_path)
        real_out = os.path.realpath(output_path)
        if real_out == real_app or real_out.startswith(real_app + os.sep):
            err("--output 不可在輸入 App 內部（移除輸出會傷到輸入）")
        if real_app == real_out or real_app.startswith(real_out + os.sep):
            err("--output 不可是輸入 App 的上層（移除輸出會傷到輸入）")

data["info"] = info
data["notes"] = notes
data["mode"] = mode

if errs:
    for message in errs:
        sys.stderr.write("輸入錯誤：%s\n" % message)
    sys.stderr.write("共 %d 項輸入錯誤，尚未做任何副作用。\n" % len(errs))
    sys.exit(2)

if mode == "execute":
    sys.stdout.write("輸入驗證通過（%d 項提醒）。\n" % len(notes))
    for message in notes:
        sys.stdout.write("  提醒：%s\n" % message)
    sys.exit(0)

# --- 計畫輸出 --------------------------------------------------------------
def masked(value):
    value = (value or "").strip()
    if len(value) <= 4:
        return "*" * len(value)
    return value[:2] + "*" * max(3, len(value) - 4) + value[-2:]


identity_display = "Developer ID Application: <已遮蔽>"
team = info.get("team_id", "")
if team:
    identity_display += " (%s)" % team

plan = {
    "mode": "plan",
    "app": {
        "path": app_path,
        "bundle_id": info.get("bundle_id", ""),
        "current_version": info.get("current_version", ""),
        "current_build": info.get("current_build", ""),
        "min_os": info.get("min_os", ""),
        "archs": info.get("archs"),
        "framework_archs": info.get("framework_archs"),
    },
    "output": {
        "path": output_path,
        "created": False,
        "staging": os.path.join(output_path, "staging"),
        "publish": os.path.join(output_path, "publish"),
    },
    "versions": {"short_version": ver, "build": build},
    "signing": {
        "identity": identity_display,
        "team_id": team,
        "notary_profile": masked(profile),
        "hardened_runtime": True,
        "secure_timestamp": True,
    },
    "sparkle": {
        "account": account,
        "public_key_fingerprint": info.get("key_fingerprint", ""),
        "public_key_matches_app": True,
        "artifact_root": info.get("artifact_root", ""),
        "artifact_version": info.get("artifact_version", ""),
        "artifact_changelog": info.get("artifact_changelog", ""),
        "artifact_framework_archs": info.get("artifact_framework_archs", []),
        "tools_sha256": info.get("tools_verified", {}),
        "pinned_version": expected_sparkle,
        "account_key_check": "執行時以 generate_keys --account ACCOUNT -p 比對；plan 不碰 Keychain",
    },
    "urls": {
        "feed_url": feed,
        "download_prefix": dlp,
        "project_link": link,
    },
    "steps": [
        "1. ditto 複製 App 到 <output>/staging/app，只改 CFBundleShortVersionString / CFBundleVersion",
        "2. 由內而外簽章（XPC → Autoupdate → Updater.app → Sparkle.framework → App），明確身分 + hardened runtime + 安全時間戳",
        "3. 產生 pre-notary ZIP（留在 staging），notarytool submit --wait，必須 Accepted，再 staple 與 spctl 驗證",
        "4. staple 之後才用 ditto 產生正式 ZIP 到 <output>/publish，sign_update --account 簽章並 --verify 驗證",
        "5. generate_appcast 於 <output>/publish，逐項比對版本、build、長度、網址與簽章，再寫 SHA256SUMS",
        "6. 只輸出發布清單（正式 ZIP + appcast.xml + SHA256SUMS）；本工具不做任何上傳",
    ],
    "not_done_by_this_tool": [
        "不建立／匯出／匯入金鑰或憑證，不碰 Keychain",
        "不新增 notary profile 或憑證",
        "不上傳、不動 git、不動 GitHub、不動發布頁面",
        "不登錄、不改登入項目、不動 TCC、不結束 App 或服務",
    ],
    "notes": notes,
}

if want_json == "1":
    import json
    sys.stdout.write(json.dumps(plan, ensure_ascii=False, indent=2) + "\n")
    sys.exit(0)

app_line = "  app             %s" % app_path
sys.stdout.write("== UTUVO Mouse 發行計畫（零副作用）==\n")
sys.stdout.write("輸入（已消毒）：\n")
sys.stdout.write(app_line + "\n")
sys.stdout.write("  bundle id       %s（保持不變）\n" % info.get("bundle_id", ""))
sys.stdout.write("  目前版本        %s (build %s)\n" % (info.get("current_version", ""),
                                                      info.get("current_build", "")))
sys.stdout.write("  新版本          %s (build %s，必須大於目前 build)\n" % (ver, build))
sys.stdout.write("  最低系統        %s\n" % info.get("min_os", ""))
sys.stdout.write("  架構            %s\n" % ",".join(info.get("archs") or ["未讀到"]))
framework_item_archs = info.get("framework_archs") or {}
sys.stdout.write("  Sparkle 架構    %s\n" % ("; ".join(
    "%s=%s" % (label, ",".join(archs) if archs else "讀不到")
    for label, archs in framework_item_archs.items()) or "-"))
sys.stdout.write("  輸出            %s（尚未建立，不會覆寫既有目錄）\n" % output_path)
sys.stdout.write("  簽章身分        %s\n" % identity_display)
sys.stdout.write("  notary profile  %s（已遮蔽）\n" % masked(profile))
sys.stdout.write("  Sparkle 帳號    %s（明確指定）\n" % account)
sys.stdout.write("  更新公鑰        sha256:%s（32 bytes，與 App 內嵌值一致）\n"
                 % info.get("key_fingerprint", ""))
sys.stdout.write("  Sparkle artifact %s\n" % (info.get("artifact_root", "") or "未提供"))
sys.stdout.write("  artifact 版本   %s（CHANGELOG：%s，預期 %s）\n"
                 % (info.get("artifact_version", "") or "未確認",
                    info.get("artifact_changelog", "") or "-",
                    expected_sparkle))
artifact_archs = info.get("artifact_framework_archs") or []
sys.stdout.write("  artifact 架構   %s\n"
                 % (",".join(artifact_archs) if artifact_archs else "-"))
sys.stdout.write("  帳號金鑰比對   執行時以 generate_keys --account ACCOUNT -p 比對（plan 不碰 Keychain）\n")
sys.stdout.write("  appcast feed    %s\n" % feed)
sys.stdout.write("  下載前綴        %s\n" % dlp)
sys.stdout.write("  專案連結        %s\n" % link)
sys.stdout.write("步驟：\n")
for step in plan["steps"]:
    sys.stdout.write("  %s\n" % step)
sys.stdout.write("本工具不做：\n")
for item in plan["not_done_by_this_tool"]:
    sys.stdout.write("  · %s\n" % item)
for message in notes:
    sys.stdout.write("  提醒：%s\n" % message)
sys.stdout.write("真正的簽章／公证／發布由 Root 在通過 UI 與裝置關卡後執行。\n")
PY
}

PLAN_STEPS_ARGS=(
    "$MODE"
    "$APP"
    "$OUT"
    "$VER"
    "$BUILD"
    "$IDENT"
    "$PROFILE"
    "$ACCOUNT"
    "$PUBKEY"
    "$KEY_FPRINT"
    "$DL_PREFIX"
    "$PROJ_LINK"
    "$FEED_OVERRIDE"
    "$TOOLS_DIR"
    "$JSON_OUT"
    "$EXPECTED_SPARKLE"
)

if [ "$MODE" = "plan" ]; then
    validate_inputs "${PLAN_STEPS_ARGS[@]}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 真正發行（Root only）。這一段不自我測試，屬於外部副作用路徑。
# ---------------------------------------------------------------------------
LOG_DIR=""
RECEIPT=""
FINAL_ZIP=""
ARCHIVE_NAME=""

log() {
    echo "==> $*"
    if [ -n "$LOG_DIR" ]; then
        echo "==> $*" >> "$LOG_DIR/execute.log"
    fi
}

run_or_fail() {
    # 失敗就停，不重試、不覆蓋、不靜默繼續。
    if [ -n "$LOG_DIR" ]; then
        echo "\$ $*" >> "$LOG_DIR/execute.log"
    fi
    if ! "$@"; then
        echo "步驟失敗：$*" >&2
        if [ -n "$LOG_DIR" ]; then
            echo "步驟失敗：$*" >> "$LOG_DIR/execute.log"
        fi
        exit 1
    fi
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "需要但找不到工具：$1"
}

for required_tool in ditto codesign xcrun plutil shasum; do
    need_tool "$required_tool"
done

validate_inputs "${PLAN_STEPS_ARGS[@]}"

# --- 執行前的必要檢查（先做完再碰任何輸出目錄）-----------------------------
CHECK_LOG="$(mktemp "${TMPDIR:-/tmp}/mouse008a-exec-check.XXXXXX")"

SIGN_UPDATE="$TOOLS_DIR/sign_update"
GENERATE_APPCAST="$TOOLS_DIR/generate_appcast"
GENERATE_KEYS="$TOOLS_DIR/generate_keys"
for tool_path in "$SIGN_UPDATE" "$GENERATE_APPCAST" "$GENERATE_KEYS"; do
    [ -x "$tool_path" ] || die "缺少可執行檔：$tool_path"
done

# 收據要記錄「實際驗了什麼」：工具雜湊與 artifact 版本來源。
SIGN_UPDATE_SHA256="$(shasum -a 256 "$SIGN_UPDATE" | awk '{print $1}')"
GENERATE_APPCAST_SHA256="$(shasum -a 256 "$GENERATE_APPCAST" | awk '{print $1}')"
GENERATE_KEYS_SHA256="$(shasum -a 256 "$GENERATE_KEYS" | awk '{print $1}')"
ARTIFACT_CHANGELOG="$(dirname "$TOOLS_DIR")/CHANGELOG"

# CLI 能力只在 execute、只對明確指定的那份官方工具檢查。
require_flag() {
    "$1" --help 2>&1 | grep -qE -- "(^|[^A-Za-z0-9_-])$2([^A-Za-z0-9_-]|\$)" \
        || die "$(basename "$1") 不支援 ${2}（先停下，不猜旗標）"
}
require_flag "$SIGN_UPDATE" --account
require_flag "$SIGN_UPDATE" --verify
require_flag "$SIGN_UPDATE" -p
require_flag "$GENERATE_APPCAST" --account
require_flag "$GENERATE_APPCAST" --download-url-prefix
require_flag "$GENERATE_APPCAST" --link
require_flag "$GENERATE_APPCAST" --maximum-deltas
require_flag "$GENERATE_KEYS" --account
require_flag "$GENERATE_KEYS" -p

# 帳號的公開金鑰必須等於 App 內嵌金鑰：只查詢（-p），絕不產生、匯出或匯入。
if ! ACCOUNT_PUBLIC_KEY="$("$GENERATE_KEYS" --account "$ACCOUNT" -p 2>"$CHECK_LOG")"; then
    echo "無法查詢帳號 $ACCOUNT 的公開金鑰（絕不自動產生金鑰）" >&2
    sed -n '1,20p' "$CHECK_LOG" >&2
    exit 1
fi
ACCOUNT_PUBLIC_KEY="$(printf '%s' "$ACCOUNT_PUBLIC_KEY" | tr -d ' \t\r\n')"
[ -n "$ACCOUNT_PUBLIC_KEY" ] || die "帳號 $ACCOUNT 查不到公開金鑰（絕不自動產生金鑰）"
[ "$ACCOUNT_PUBLIC_KEY" = "$PUBKEY" ] \
    || die "帳號 $ACCOUNT 的公開金鑰與 App 內嵌的 SUPublicEDKey 不一致"

APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
STAGING_DIR="$OUT_ABS/staging"
PUBLISH_DIR="$OUT_ABS/publish"
LOG_DIR="$STAGING_DIR/logs"
RECEIPT="$OUT_ABS/release-receipt.txt"

ARCHIVE_NAME="UTUVO-Mouse-${VER}-${BUILD}.zip"
FINAL_ZIP="$PUBLISH_DIR/$ARCHIVE_NAME"

mkdir -p "$LOG_DIR"
mkdir -p "$PUBLISH_DIR"
cp "$CHECK_LOG" "$LOG_DIR/execute-checks.log"
rm -f "$CHECK_LOG"

# 選定的 feed：覆寫優先，否則用 App 內嵌的值（驗證階段已檢查過 https 與主機）。
if [ -n "$FEED_OVERRIDE" ]; then
    SELECTED_FEED="$FEED_OVERRIDE"
else
    SELECTED_FEED="$(plutil -extract SUFeedURL raw -o - "$APP_ABS/Contents/Info.plist" 2>/dev/null || true)"
fi
[ -n "$SELECTED_FEED" ] || die "無法決定選定的 feed URL"

# --- 1. 複製 App ------------------------------------------------------------
STAGED_APP="$STAGING_DIR/app/$APP_NAME_EXPECTED.app"
log "複製 App 到暫存區"
mkdir -p "$(dirname "$STAGED_APP")"
run_or_fail ditto "$APP_ABS" "$STAGED_APP"

# 只改兩個版本欄位，其他一律不動。
run_or_fail /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" \
    "$STAGED_APP/Contents/Info.plist"
run_or_fail /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" \
    "$STAGED_APP/Contents/Info.plist"

NEW_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$STAGED_APP/Contents/Info.plist")"
[ "$NEW_BUNDLE_ID" = "$BUNDLE_ID_EXPECTED" ] || die "bundle id 被改動：$NEW_BUNDLE_ID"
NEW_KEY="$(plutil -extract SUPublicEDKey raw -o - "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$NEW_KEY" = "$PUBKEY" ] || die "App 內嵌公鑰在複製後不一致"

# feed 覆寫要真的套用到暫存 App（plutil 寫入，XML 安全），套用後必須與選定值一致。
if [ -n "$FEED_OVERRIDE" ]; then
    run_or_fail plutil -replace SUFeedURL -string "$FEED_OVERRIDE" \
        "$STAGED_APP/Contents/Info.plist"
fi
STAGED_FEED="$(plutil -extract SUFeedURL raw -o - "$STAGED_APP/Contents/Info.plist")"
[ "$STAGED_FEED" = "$SELECTED_FEED" ] \
    || die "暫存 App 的 SUFeedURL 與選定 feed 不一致：$STAGED_FEED"

# --- 2. 由內而外簽章 -------------------------------------------------------
FRAMEWORK="$STAGED_APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_BIN="$FRAMEWORK/Versions/B"
[ -d "$FRAMEWORK_BIN" ] || die "找不到 Sparkle.framework 的 Versions/B：$FRAMEWORK_BIN"

sign_item() {
    local item="$1"
    log "簽章 $(basename "$item")"
    # 明確身分、hardened runtime、安全時間戳；保留既有 entitlements。
    run_or_fail codesign --force --options runtime --timestamp \
        --sign "$IDENT" --preserve-metadata=entitlements "$item"
    run_or_fail codesign --verify --strict "$item"
}

sign_item "$FRAMEWORK_BIN/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
sign_item "$FRAMEWORK_BIN/XPCServices/Downloader.xpc"
sign_item "$FRAMEWORK_BIN/XPCServices/Installer.xpc/Contents/MacOS/Installer"
sign_item "$FRAMEWORK_BIN/XPCServices/Installer.xpc"
sign_item "$FRAMEWORK_BIN/Autoupdate"
sign_item "$FRAMEWORK_BIN/Updater.app/Contents/MacOS/Updater"
sign_item "$FRAMEWORK_BIN/Updater.app"
sign_item "$FRAMEWORK_BIN/Sparkle"
sign_item "$FRAMEWORK"
run_or_fail codesign --force --options runtime --timestamp --sign "$IDENT" \
    --preserve-metadata=entitlements "$STAGED_APP"
# --deep 只用於驗證，簽章永遠不用 --deep。
run_or_fail codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

# 簽章結果的公開收據：權威、team id、designated requirement。
{
    echo "# codesign -dv 收據（公開資訊，無秘密）"
    codesign -dv --verbose=4 "$STAGED_APP" 2>&1 | grep -E '^(Authority|TeamIdentifier|Identifier|CDHash)='
    echo "# designated requirement"
    codesign -d -r- "$STAGED_APP" 2>&1 | sed -n '/^designated =/,$p'
} > "$STAGING_DIR/codesign-receipt.txt"

APP_TEAM="$(codesign -dv --verbose=4 "$STAGED_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
[ -n "$APP_TEAM" ] || die "外層簽章沒有 TeamIdentifier"
codesign -dv --verbose=4 "$STAGED_APP" 2>&1 | grep -q '^Authority=Developer ID Application' \
    || die "外層簽章權威不是 Developer ID Application"

# 巢狀項目必須是同一個 team。
for nested in "$FRAMEWORK_BIN/XPCServices/Downloader.xpc" \
             "$FRAMEWORK_BIN/XPCServices/Installer.xpc" \
             "$FRAMEWORK_BIN/Autoupdate" \
             "$FRAMEWORK_BIN/Updater.app" \
             "$FRAMEWORK"; do
    nested_team="$(codesign -dv --verbose=4 "$nested" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
    [ "$nested_team" = "$APP_TEAM" ] || die "巢狀簽章 team 不一致：$nested ($nested_team)"
done

# --- 3. 公证 ----------------------------------------------------------------
log "產生 pre-notary ZIP（留在 staging，不進發布目錄）"
PRE_ZIP="$STAGING_DIR/pre-notary-$VER-$BUILD.zip"
run_or_fail ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$PRE_ZIP"

log "送出公证（notarytool --wait --output-format json）"
NOTARY_JSON="$STAGING_DIR/notary-$VER-$BUILD.json"
# 真正的 notarytool 沒有 --output-file，JSON 一律從 stdout 收。
if ! NOTARY_OUTPUT="$(xcrun notarytool submit "$PRE_ZIP" --keychain-profile "$PROFILE" \
        --wait --output-format json 2>"$LOG_DIR/notarytool.log")"; then
    echo "notarytool 失敗，詳見 $LOG_DIR/notarytool.log" >&2
    exit 1
fi
printf '%s\n' "$NOTARY_OUTPUT" > "$NOTARY_JSON"
NOTARY_STATUS="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as handle:
        data = json.load(handle)
except Exception as exc:
    print("PARSE_ERROR: %s" % exc)
    raise SystemExit(0)
print(data.get("status", ""))
' "$NOTARY_JSON")"
[ "$NOTARY_STATUS" = "Accepted" ] || die "公证狀態不是 Accepted：$NOTARY_STATUS"

log "staple 與評估"
run_or_fail xcrun stapler staple "$STAGED_APP"
run_or_fail xcrun stapler validate "$STAGED_APP"
run_or_fail codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
run_or_fail spctl --assess --type execute --verbose=4 "$STAGED_APP"

# --- 4. 正式 ZIP 與更新簽章 -------------------------------------------------
log "產生正式 ZIP"
run_or_fail ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$FINAL_ZIP"

SIGN_UPDATE="$TOOLS_DIR/sign_update"
GENERATE_APPCAST="$TOOLS_DIR/generate_appcast"
[ -x "$SIGN_UPDATE" ] || die "缺少 $SIGN_UPDATE"
[ -x "$GENERATE_APPCAST" ] || die "缺少 $GENERATE_APPCAST"

# 旗標是否齊備已經在輸入驗證階段確認過（fail-closed，不猜旗標）。

log "用 sign_update 簽章正式 ZIP"
if ! ED_SIGNATURE="$("$SIGN_UPDATE" --account "$ACCOUNT" -p "$FINAL_ZIP" 2>"$LOG_DIR/sign_update.log")"; then
    echo "sign_update 簽章失敗，詳見 $LOG_DIR/sign_update.log" >&2
    exit 1
fi
[ -n "$ED_SIGNATURE" ] || die "sign_update 沒有回傳簽章"
printf '%s\n' "$ED_SIGNATURE" > "$STAGING_DIR/ed-signature.txt"
# 驗證一定要用同一個 --account，否則驗的不是同一把金鑰。
run_or_fail "$SIGN_UPDATE" --account "$ACCOUNT" --verify "$FINAL_ZIP" "$ED_SIGNATURE"

# --- 5. appcast 與校驗 ------------------------------------------------------
log "產生 appcast"
run_or_fail "$GENERATE_APPCAST" --account "$ACCOUNT" \
    --download-url-prefix "$DL_PREFIX" --link "$PROJ_LINK" \
    --maximum-deltas 0 "$PUBLISH_DIR"

APPCAST="$PUBLISH_DIR/appcast.xml"
[ -f "$APPCAST" ] || die "沒有產生 appcast.xml"

python3 - "$APPCAST" "$VER" "$BUILD" "$FINAL_ZIP" "$DL_PREFIX" "$PUBKEY" "$STAGED_APP" \
    "$ED_SIGNATURE" <<'PY'
import base64
import os
import plistlib
import sys
import xml.etree.ElementTree as ET

appcast, version, build, archive, prefix, public_key, staged_app, verified_signature = \
    sys.argv[1:9]

# 真實 Sparkle appcast（見官方 SampleAppcast.xml）：<rss xmlns:sparkle="...">，
# sparkle:version / sparkle:shortVersionString 是 <item> 的子元素；
# url / length 是無命名空間屬性；sparkle:edSignature 是帶前綴的屬性。
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def child_text(item, name):
    element = item.find(NS + name)
    if element is None:
        element = item.find("sparkle:" + name)
    if element is None:
        return None
    return (element.text or "").strip()


def attr(element, name):
    for candidate in (NS + name, "sparkle:" + name, name):
        value = element.get(candidate)
        if value is not None:
            return value
    return None


size = os.path.getsize(archive)
root = ET.parse(appcast).getroot()
items = root.findall("./channel/item")
if not items:
    items = root.findall(NS + "channel/" + NS + "item")
if not items:
    sys.exit("appcast 沒有任何 item")

matches = []
for item in items:
    enclosure = item.find("enclosure")
    if enclosure is None:
        enclosure = item.find(NS + "enclosure")
    if enclosure is None:
        continue
    item_build = child_text(item, "version")
    item_short = child_text(item, "shortVersionString")
    if item_build == build and (item_short is None or item_short == version):
        matches.append((item, enclosure, item_short))

if len(matches) != 1:
    sys.exit("appcast 內符合版本 %s (%s) 的項目不是 1 個，而是 %d 個"
             % (version, build, len(matches)))

item, enclosure, item_short = matches[0]
if item_short is not None and item_short != version:
    sys.exit("appcast 的 shortVersionString 與目標版本不符：%s" % item_short)

if int(attr(enclosure, "length") or "-1") != size:
    sys.exit("appcast 長度 %s 與實際 ZIP 大小 %d 不符"
             % (attr(enclosure, "length"), size))

url = attr(enclosure, "url") or ""
if not url.startswith(prefix):
    sys.exit("appcast 網址不在下載前綴內：%s" % url)
if not url.endswith(os.path.basename(archive)):
    sys.exit("appcast 網址指向的檔名不是正式 ZIP：%s" % url)

signature = (attr(enclosure, "edSignature") or "").strip()
try:
    raw = base64.b64decode(signature, validate=True)
except Exception:
    sys.exit("appcast 的 EdDSA 簽章不是合法 base64")
if len(raw) != 64:
    sys.exit("appcast 的 EdDSA 簽章長度不是 64 bytes：%d" % len(raw))
# 必須與先前用 sign_update --verify（同一個 --account）驗證過的簽章完全一致。
if signature != verified_signature.strip():
    sys.exit("appcast 的簽章與已驗證的簽章不一致（長度或金鑰對不上）")

with open(os.path.join(staged_app, "Contents", "Info.plist"), "rb") as handle:
    plist = plistlib.load(handle)
if str(plist.get("SUPublicEDKey", "")).strip() != public_key:
    sys.exit("App 內嵌公鑰與簽章用的公鑰不一致")
if str(plist.get("CFBundleShortVersionString", "")) != version or \
   str(plist.get("CFBundleVersion", "")) != build:
    sys.exit("App 內嵌版本與 appcast 不一致")
if str(plist.get("CFBundleIdentifier", "")) != "com.utuvo.mouse":
    sys.exit("App bundle id 被改動")
if not str(plist.get("SUFeedURL", "")).strip():
    sys.exit("暫存 App 沒有 SUFeedURL")

print("appcast 校驗通過：版本 %s (%s)、長度 %d、簽章與已驗證簽章一致、網址前綴相符"
      % (version, build, size))
PY

# --- 6. 校驗碼與發布清單 ----------------------------------------------------
ZIP_SHA="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$ZIP_SHA" "$ARCHIVE_NAME" > "$PUBLISH_DIR/SHA256SUMS"

{
    echo "# UTUVO Mouse 發行收據（公開資訊，無秘密）"
    echo "版本        $VER (build $BUILD)"
    echo "bundle id   $BUNDLE_ID_EXPECTED"
    echo "team id     $APP_TEAM"
    echo "公鑰指紋    sha256:$(printf '%s' "$PUBKEY" | base64 -d | shasum -a 256 | awk '{print $1}')"
    echo "Sparkle 帳號 ${ACCOUNT}（帳號公開金鑰指紋與上面相同）"
    echo "feed        $SELECTED_FEED"
    echo "正式 ZIP    $ARCHIVE_NAME"
    echo "長度        $(stat -f%z "$FINAL_ZIP")"
    echo "SHA256      $ZIP_SHA"
    echo "EdDSA 簽章  $(cat "$STAGING_DIR/ed-signature.txt")"
    echo "公證狀態    $NOTARY_STATUS"
    echo "Sparkle     ${EXPECTED_SPARKLE}（${ARTIFACT_CHANGELOG}）"
    echo "工具 SHA256  sign_update=$SIGN_UPDATE_SHA256"
    echo "             generate_appcast=$GENERATE_APPCAST_SHA256"
    echo "             generate_keys=$GENERATE_KEYS_SHA256"
    echo "appcast     $APPCAST"
} > "$RECEIPT"

log "發布清單（本工具不上傳）"
( cd "$PUBLISH_DIR" && ls -1 )
echo "私有暫存（不發布）：$STAGING_DIR"
echo "收據：$RECEIPT"
echo "接下來由 Root 手動上傳發布清單內的三個檔案，並自行執行 spctl／安裝與更新驗證。"
