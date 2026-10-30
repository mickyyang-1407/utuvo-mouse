# First device handoff / 第一台實機交接

This is the next step for an owner's AI when an MX Anywhere 3 is available.
The stable **0.3.3 download does not contain this workflow**. The reviewed source
preview has read-only inspection and report import, but no Anywhere 3 settings.
Current binary support is Apple Silicon, macOS 14+, with Swift 6.2+ to build.
Windows, Linux and Intel Mac behavior is unverified.

可把下方整段交給滑鼠擁有者的 AI。它會先準備隔離預覽，再取得本人同意才讀取滑鼠；
不需要 Micky 重做已完成的插線、按鍵或系統授權測試。

## Copy to the owner's AI

> Prepare one read-only capability report from my MX Anywhere 3 for UTUVO Mouse.
> First check the OS, architecture and build tools. This preview targets an
> Apple Silicon Mac with macOS 14+ and Swift 6.2+. If those prerequisites are
> absent, report the missing prerequisite; do not attempt another platform or
> install toolchains automatically.
>
> Use a new private temporary directory, clone the public preview below and
> check out the pinned reviewed source. Do not reset or reuse an existing
> checkout. Build the isolated app and run the help command first. Do not open
> the GUI or replace any installed UTUVO Mouse app.
>
> Before running the live inspection, obtain the actual mouse owner's explicit
> consent once unless already given. Ask the owner to connect their MX Anywhere 3
> by Bluetooth and keep it awake. This path covers exactly 046D:B025 Bluetooth;
> USB, receivers and other variants must not be forced through it.
>
> Run the live inspection once. On failure, stop and show the fixed diagnostic
> code. Do not reset TCC, toggle permissions, quit vendor agents, intercept
> input, change pairing/settings/firmware or broaden the device match. macOS
> authentication and any permission decision belong to the owner.
>
> On success, import the JSON into the isolated queue below and show the owner
> the report JSON and import summary. Do not send or publish them automatically.
> Do not substitute sample data or infer missing fields. A successful report
> establishes read-only inspection only, not configuration behavior or a release.

Run these preparation commands sequentially, stopping on an error:

```sh
set -eu
utuvo_probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/utuvo-mouse-inspection.XXXXXX")"
printf 'Inspection working directory: %s\n' "$utuvo_probe_dir"
git clone --branch codex/model-support-preview \
  https://github.com/mickyyang-1407/utuvo-mouse.git "$utuvo_probe_dir/source"
cd "$utuvo_probe_dir/source"
git checkout --detach d148ff53902415376367994b6360cc709857de61
BUILD_MODE=dev BUILD_DIR="$utuvo_probe_dir/preview" bash scripts/build.sh
utuvo_preview_bin="$utuvo_probe_dir/preview/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse"
"$utuvo_preview_bin" --inspect-capabilities --help
```

Only after the owner has consented, run once. Continue to the import only if
inspection exits successfully. These blocks share shell variables; an AI using
separate shell calls must restore `utuvo_probe_dir` from the printed path and
derive `utuvo_preview_bin` again before this step.

```sh
set -eu
if "$utuvo_preview_bin" --inspect-capabilities 046d-b025-bluetooth \
  --allow-read-only-hidpp > "$utuvo_probe_dir/capability-report.json"; then
  "$utuvo_preview_bin" --import-capabilities "$utuvo_probe_dir/capability-report.json" \
    --support-directory "$utuvo_probe_dir/queue"
else
  exit 1
fi
```

The report contains model IDs, transport, protocol version and feature IDs. It
must not include serial numbers, Bluetooth addresses, personal device names,
settings, raw frames or local paths. Import always marks it `imported`; a file
handoff never becomes device confirmation or physical verification.

After the report is available, the existing
[developer companion](MODEL-SUPPORT.md#developer-setup) can create and test a
source candidate. Exact-model physical checks, restoration and reviewed signed
delivery remain required. This handoff does not run a coding agent, install a
background worker or change login/updater preferences.
