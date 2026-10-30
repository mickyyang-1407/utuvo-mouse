# MX Anywhere 3 Bluetooth — read-only preview

This source preview provides an explicit capability-inspection command for
VID `046D`, PID `B025`, exact Bluetooth mouse collections. It does not add this
mouse to automatic device opening or configuration support. No physical
MX Anywhere 3 was available during development; the input was an upstream
research seed, not a detected device.

本預覽只有明確同意的唯讀能力檢查，尚未實機驗證，也沒有 DPI、SmartShift、滾輪或按鍵
設定控制。啟動與自動辨識維持被動路徑；只有明確執行檢查指令或點選「收集能力」才會查詢。

For an owner's AI starting from a download, use the
[first-device handoff](AI-FIRST-DEVICE.md). It identifies the preview source and
keeps the existing installed app intact.

## Build and inspect

Build this preview branch with the existing [build instructions](../README.md#build).
Help and missing-consent paths exit before GUI setup and hardware discovery:

```sh
"build/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse" --inspect-capabilities --help
```

Only after the device owner explicitly authorizes a live read, use:

```sh
"build/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse" \
  --inspect-capabilities 046d-b025-bluetooth --allow-read-only-hidpp
```

The argument order is exact. macOS permissions remain under the device owner's
control. The command never changes TCC, vendor agents, settings, pairing or
firmware. It opens at most one eligible device without seizure; multiple
candidates fail as ambiguous. USB/receiver variants and vendor HID collections
are not covered by this preview.

## Report and failure semantics

A complete read prints a model-level JSON report: IDs, transport, protocol
major/minor, sorted feature IDs, `readOnly=true` and
`configurationWritesEnabled=false`. It omits serial/address/unit hash, device
name, raw replies and settings. Failure prints a fixed bilingual diagnostic code
and returns nonzero, with no successful partial report. No report file or
preferences are saved automatically.

This capability report is a **separate schema** from the developer queue's
`report.json`; do not copy it directly into that queue. It can be handed to the
queue through the explicit import route, which validates it, stores it as
`capabilities.json` with imported provenance and never treats it as a device
confirmation:

```sh
"build/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse" \
  --import-capabilities /path/to/report.json \
  --support-directory /path/to/queue
```

See [model support](MODEL-SUPPORT.md#capability-records) for the stored schema,
the input fingerprint and the companion's rules. Physical validation records
remain future work.

Only ROOT protocol-version/feature-resolution and FEATURE_SET count/ID getters
are sent. There are at most 64 non-ROOT features / 67 requests, each with at most
400 ms reply wait, without retries. The conservative parser accepts major 2/4,
minor 0–9; other versions fail. OS open/send overhead is not a hard wall-clock
deadline. A successful read establishes no configuration support or physical
effect. Direct `FF` reply indexing, generic collection, exact transport spelling,
long-report support, disconnect behavior and normal operation during inspection
still require real-device checks.

## Evidence and sources

The actual configured Codex CLI produced the original read-only inspection
candidate from public/synthetic inputs. Its companion built that source and ran
**167 mock/synthetic tests in 28 suites** under its separate OS sandbox. Five
actual executable help/consent/wrong-model/mixed-mode gates passed without a
consented hardware invocation.

The later capability-report handoff was implemented separately and passed
**197 mock/synthetic Swift tests in 30 suites** and **24 isolated companion
fixtures**. Its report-driven agent runs use a fake agent; they do not prove a
second real Codex run or a physical mouse query. Independent executable import
checks used the test OS sandbox and a synthetic fingerprint oracle. These later
results must not be attributed to the earlier real-Codex trial.
An isolated Core Foundation timer fixture also checked async main-run-loop
behavior. Independent source review passed. These are program evidence, not
physical evidence, an installed update or a public binary release.

Identity/protocol facts were cross-checked against
[Solaar's B025 report](https://github.com/pwr-Solaar/Solaar/blob/master/docs/devices/MX%20Anywhere%203%20B025.txt),
[libratbag's device definition](https://github.com/libratbag/libratbag/blob/master/data/devices/logitech-MX-Anywhere-3.device),
and [Logitech's HID++ documentation](https://github.com/Logitech/cpg-docs/blob/master/hidpp20/README.rst).
Feature IDs and versions in a successful report come from replies, not these
examples. No GPL implementation code or upstream device identifiers/settings
were copied. New configuration paths, physical verification and signed update
delivery remain separate gates.
