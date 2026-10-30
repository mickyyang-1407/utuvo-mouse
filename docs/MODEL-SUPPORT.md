# New-model support / 新型號支援

The long-term goal is a complete path from a newly connected mouse to a reviewed,
physically verified, signed update. MX Anywhere 3 is the first target. This
candidate implements the local task mailbox and developer companion; it does
**not** claim that MX Anywhere 3 configuration is supported yet.

Preview source: `codex/model-support-preview`. The published 0.3.3 app does not
contain this workflow. The draft preview has passed 197 synthetic Swift tests in
30 suites, 24 companion fixtures, one actual configured-Codex candidate run, and
independent source review. Physical MX Anywhere 3 inspection remains unverified.

長期目標是：接上新滑鼠 → 開發 AI 加入支援 → 隔離測試 → 實機驗證 → 審查與簽章更新。
首例為 MX Anywhere 3。本候選版實作本機任務及開發端 companion，尚未宣稱 Anywhere 3 可設定。

Have the mouse available on another Mac? Use the
[copyable first-device handoff for its owner's AI](AI-FIRST-DEVICE.md) to collect
the missing report from the reviewed preview, without replacing an installed app.

## What the app does

- A newly observed, unsupported Logitech mouse creates one local task per
  VID/PID/transport in `~/Library/Application Support/UTUVOMouse/ModelSupport`.
- Settings → New model support can disable local task preparation. This does not
  delete an existing task or stop a separately running developer companion.
- Reports include only numeric model IDs, connection type, a fixed catalog hint
  when known, and observed feature IDs. Reports omit serial numbers, Bluetooth
  addresses, unit hashes, personal device names, raw HID packets and settings.
- Unknown devices remain on the existing passive inventory path: this feature
  does not open them or discover capabilities by sending commands. Empty feature
  IDs mean “not queried,” not “no features.” Generic receivers may need paired
  device identification before a model task can proceed.
- The app makes no upload and launches no coding agent. A developer must configure
  the companion with their own authenticated Codex CLI. Their provider processes
  the supplied metadata/source under that account's settings.
- Status updates on app activation or Refresh status. No new timer, background
  AI process or network service is added to the normal app.

App 只在本機建立任務，不會上傳，也不會啟動 AI。開發者完成下列設定並啟動 companion
後，才會自動處理新任務。報告不含個人識別資料；未知型號維持唯讀。

## Capability records

A model job may carry one extra file, `capabilities.json`, next to `report.json`.
It is the validated capability report of that exact model, stored as an envelope
with exactly five fields:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `1` |
| `origin` | `appReadOnly` (collected in the app) or `imported` (a file) |
| `report` | the allowlisted report: model key, VID/PID, transport, protocol major/minor, sorted feature IDs, `readOnly=true`, `configurationWritesEnabled=false` |
| `hardwareBehaviorVerified` | always `false` |
| `released` | always `false` |

The record is validated by the same Support-layer rules on the way in and on the
way out: allowlisted keys and exact types only, at most 16 KiB, no extra private
fields, no foreign model/vendor/product/transport, `readOnly` must be `true`,
`configurationWritesEnabled` must be `false`, protocol major 2 or 4 with minor
0–9, and feature IDs that are unique, sorted, uppercase four-digit hex and
include both ROOT (`0000`) and FEATURE_SET (`0001`). A JSON boolean never
passes as an integer and a number never passes as a boolean. No field and no
file can enable a configuration write, a hardware claim or a release.

The envelope contains no timestamp, name, serial, unit ID, address, local path,
setting or raw frame.

### Input fingerprint

One canonical string identifies an input revision. It is the UTF-8 SHA-256 of:

```text
v1\n<modelKey>\n<origin>\n<major>.<minor>\n<comma-joined sorted feature IDs>
```

with no trailing newline. The Swift app and the Python companion compute the
same value; `Tests/fixtures/capability-fingerprint.json` pins one example for
both. The fingerprint appears in every status and result as
`capabilitiesFingerprint`. Old jobs and old statuses simply have none.

### Collecting and importing

The app has one explicit **Collect capabilities** button, only for exactly
`046D:B025` over Bluetooth, only when the local queue is enabled, not in demo
mode and not while another collection runs. Only that button calls the
read-only inspection service; observation, start, refresh and the tests never
do. A failed collection saves no successful record.

A report file can also be handed to the queue from the command line. This route
is consumed before any app setup, before the inspection command and before
`--probe`:

```sh
"build/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse" \
  --import-capabilities /path/to/report.json \
  --support-directory /path/to/queue
```

`--support-directory` selects an isolated local developer queue; the default is
the app's own queue. The file must be a bounded regular non-symlink file. Mixed
modes and malformed arguments are refused before anything else happens, and a
failure prints a fixed code only — never the path, the file name or the file
content. The output contains the model key, the input fingerprint and the fixed
pending gates.

An imported record keeps `origin: imported` forever. Importing is a handoff of
a file, never a device confirmation.

### What the companion does with it

The companion loads `capabilities.json` when it exists, validates it strictly,
and passes only the normalized safe values and their provenance into the coding
prompt. A metadata-only job without the file keeps working unchanged. A stored
record whose model key does not match its own job directory is refused: it is
never that job's input. The file must be one regular file and is read within a
bounded size; an oversized, symlinked or non-regular file is refused instead of
being read.

* A terminal job (`needsHardware` or `failed`) whose stored fingerprint matches
  the current file is skipped. Re-importing the same report never runs the
  agent again and never spends anything.
* A new fingerprint is one new input revision: the previous `status.json` and
  `result.json` are moved into a local `history/` folder and exactly one
  follow-up runs. The archived evidence keeps the old progress.
* A change that arrives while a run is active waits for the next pass. The
  running job records the fingerprint it actually used, so its program tests
  are never presented as covering the newer input.
* Interrupted jobs stay failed, and terminal jobs are never retried in a loop.

The unknown-model page keeps four states apart: the capability report with its
provenance, the program test of the current input, physical behaviour (always
unverified) and the release (always not released). An imported report never
gets a physical-success mark.

The program wording never claims more than the input allows:

* A stored capability file that cannot be validated is reported per model as an
  invalid capability input. The program coverage is unavailable, and the stored
  result is never presented as covering it.
* A capability input that is newer than the tested revision states that tests
  for the latest input are pending. The earlier result stays visible, marked as
  an earlier input.
* A removed capability file never shows a current-input success. A legacy
  status without a fingerprint stays compatible and is identified as covering
  metadata only.
* The 64-character input fingerprint is not shown in the product pane. It stays
  in the developer JSON output, in `status.json` and in `result.json`.

## Developer setup

Build and run this preview branch using the README build instructions first.
The stable 0.3.3 download does not create these tasks or collect these reports.


Requires macOS, Python 3.10+, Git, Swift, `sandbox-exec`, and an installed,
authenticated Codex CLI. The source checkout must be clean and committed; the
candidate directory must be separate from both source and task queue.

```sh
git clone --branch codex/model-support-preview https://github.com/mickyyang-1407/utuvo-mouse.git
cd utuvo-mouse
python3 scripts/model-support-worker.py \
  --source "$PWD" \
  --queue "$HOME/Library/Application Support/UTUVOMouse/ModelSupport" \
  --candidates "$HOME/utuvo-mouse-candidates" \
  --watch
```

Use `--once` instead of `--watch` for one pass. Ctrl-C stops the companion and its
active child process group. `--watch` checks every 15 seconds. It is an explicit
developer process, not an installed login agent; the app's existing login switch
still controls only UTUVO Mouse. No extra AI subscription or API key is bundled.

The companion regenerates its prompt from validated report fields, never from an
arbitrary device name or an edited TASK.md. It clones committed source without
hard links, resolves the existing pinned dependencies, then runs Codex with the
workspace-write sandbox. A second outer Seatbelt wrapper would prevent Codex's
file/shell helpers from starting on macOS, so the CLI is not nested inside
`sandbox-exec`. Live-device and GUI operations are forbidden by the coding task;
the separate test process has the OS-level IOKit denial described below.
GUI/communication MCP connectors are disabled for this coding-only invocation
with a process-local `mcp_servers={}` override. It does not specify a model or
replace the developer's provider configuration. It refuses changes to the manifest, pinned dependencies,
release scripts, updater configuration, Git hooks/config, resolved dependency
sources/artifacts or existing tests; additional tests are
allowed. Compilation uses the frozen manifest with IOKit/network/Keychain access
blocked, and may write compiler-managed caches. Candidate code then executes
under a stricter test sandbox that permits writes to the candidate, dedicated
test root, and macOS's two OS-managed atomic-replacement staging directories
(`TemporaryItems` / `.TemporaryItems`), while blocking writes elsewhere and reads
elsewhere in the user's home directory. Tests use the explicit
per-run `UTUVO_MOUSE_TEST_TEMP_ROOT` fixture root because macOS Foundation may
ignore `TMPDIR` under a custom sandbox. Ordinary `swift test` retains its system
temporary-directory fallback. A failure remains a failure; there is no
unsandboxed retry.

`--agent` may select a trusted Codex CLI executable, not a command string. Agent
and test timeouts kill their complete process group; background children are
also stopped when the root command finishes successfully. One file lock prevents two
companions processing the same queue. Interrupted jobs are retained as failed;
there is no automatic infinite retry or repeated AI spending. To retry, inspect
and preserve result/candidate logs, then explicitly remove that job's
`status.json` and `result.json` while the companion is stopped.

Local developer logs can contain model-generated/source content and local paths;
they are not automatically shared or included in the app's minimal report.

## Progress and acceptance

| Phase | Meaning |
| --- | --- |
| queued | Local task ready, companion not yet processing |
| preparing | Isolated source clone and pinned dependencies |
| developing | Developer AI preparing source changes |
| testing | Companion running isolated program tests |
| needsHardware | Program tests passed; physical verification outstanding |
| failed | Stopped; inspect result.json and private local logs |

A worker status cannot represent “hardware verified” or “released.” Both are
always false. Program tests, mocks, an agent's report and device ACKs cannot
establish physical behavior. A candidate must still receive independent source
review and physical evidence for the exact model/transport/functions, including
restoration of changed settings. Only then can the maintainer use the existing
notarized/Sparkle-signed release process. The companion cannot merge, sign,
publish, install or alter the running app. Automatic updating continues to accept
the project's signed releases, not locally generated drivers or arbitrary code.

## MX Anywhere 3 research seed

Solaar's [published B025 device report](https://github.com/pwr-Solaar/Solaar/blob/master/docs/devices/MX%20Anywhere%203%20B025.txt)
records Bluetooth ID B025, paired WPID 4090 and features including 2201, 2111,
2121 and 1B04. This is an upstream observation, not this app's hardware evidence.
The app uses B025/Bluetooth only as a research hint. It grants no new
configuration permission. Other variants/transports require their own identity
and capability evidence. Do not copy GPL implementation code into this MIT
project; use protocol facts and independently implement them with attribution.

## Isolated verification

```sh
swift test
python3 scripts/test-model-support-worker.py
```

The Python suite uses temporary repositories, a fake coding agent and a real
Swift fixture test run. It never invokes an AI account, live mouse, signing key,
system permission dialog or release endpoint. It proves the companion mechanics,
not that an actual AI has implemented a model successfully. The import route is
smoke-tested against an isolated `--support-directory`, never against the app's
own queue.

The macOS runtime uses SwiftPM's existing
[Swift Testing helper](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/swiftpm-testing-helper/Entrypoint.swift)
to load the compiled test image under the sandbox; it does not ask `swift test`
to regenerate its build plan during the restricted test run.
