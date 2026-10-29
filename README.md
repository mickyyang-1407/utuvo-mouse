# UTUVO Mouse

A small native macOS controller for Logitech MX Master 4 for Mac and PRO X2 SUPERSTRIKE. Local only: no account, cloud profiles, updater, telemetry, RGB, macros, or preset marketplace. Independent software, not affiliated with Logitech.

**Experimental 0.1.0 candidate. Hardware validation is in progress; this is not yet a general recommendation to replace the vendor software.**

## Controls

- Both mice: connection and battery status.
- MX Master 4 M: DPI, SmartShift, wheel direction/high resolution, middle/back/forward mapped to Copy or Paste while the app runs.
- PRO X2 SUPERSTRIKE: left/right HITS actuation, Rapid Trigger and haptics; onboard DPI, report rate, and auxiliary button assignments.
- Onboard writes are backed up and read back byte for byte. Incomplete reads and uncertain writes are displayed as unknown.

## Build and run

Requires macOS 14 or later and Swift 6.2 or later. Development and hardware checks have only run on one Apple Silicon Mac with macOS 27; other macOS versions and Intel have not been validated. No external Swift packages are needed.

```sh
swift test
bash scripts/build.sh
open "build/UTUVO Mouse.app"
```

The local build is ad-hoc signed, not notarized. Rebuilding can require you to re-enable macOS permissions. For read-only diagnostics or synthetic UI:

```sh
"build/UTUVO Mouse.app/Contents/MacOS/UTUVO Mouse" --probe
open "build/UTUVO Mouse.app" --args --demo --appearance light
```

`--probe` reads devices without changing settings. `--demo` shows synthetic data and disables writes.

## Permissions and use

Enable Input Monitoring when macOS refuses access to the MX Bluetooth interface. MX Copy/Paste mappings also require Accessibility permission. macOS handles Touch ID/password confirmation; the app does not grant its own permissions or install a privileged helper.

Quit Options+ and G HUB device agents before applying settings. Vendor software can overwrite settings when it starts again. SUPERSTRIKE in host mode displays a stored profile, which is not the active profile; explicitly select onboard mode before changing it.

The Cancel changes (取消變更) buttons discard unsaved edits. They do not restore a previous flash backup; to return to previous values, explicitly apply those values again. Backups are stored under `~/Library/Application Support/UTUVO Mouse/Backups`, with temporary mapping leases under `Diversions`.

## Verified scope and limitations

- 61 isolated tests in 13 suites pass. Tests use mock transports and temporary files, without accessing hardware.
- Real MX Bluetooth DPI 1000→1050→1000 was read back; restarting Options+ reapplied its saved 3200 DPI.
- Real SUPERSTRIKE USB stored DPI 1200→1250→1200 was read back; complete 255-byte profile and 255-byte control sectors matched their original backups, and host mode was restored.
- HITS and physical side-button validation: **pending**. No claim of everyday readiness until these checks and restoration are complete.
- Rapid Trigger may keep returning its last level after Off; a cached positive number cannot prove the switch is on. The UI requires an explicit selection and does not claim the switch state was verified.
- LIGHTSPEED receiver returned BUSY; the cause and wireless write path are unverified. Bluetooth support listed above is for the MX, not a claim of SUPERSTRIKE Bluetooth support.
- Actual pointer sensitivity, click feel, extended daily use, sleep/wake, crash recovery, other devices/firmware, Intel and other macOS versions are not yet accepted.
- Temporary MX mappings are restored on normal disable/quit after verification. Disconnects or crashes can leave uncertain state; the app retains its lease and may require a mouse power cycle/reconnect. It does not take over a button already diverted by another application.

## 繁體中文

把兩隻滑鼠的必要設定放在一個原生 App。所有設定留在本機，沒有帳號、雲端、商店或巨集。這是實驗候選；目前 DPI讀回與板載還原已驗證，HITS、側鍵與日常使用驗收仍進行中。先退出原廠裝置代理，再開啟本 App調整；輸入監控與輔助使用權限需由你在系統設定手動允許。

## License

MIT. See [LICENSE](LICENSE), [third-party notices](THIRD-PARTY-NOTICES.md) and [protocol sources](docs/PROTOCOL-SOURCES.md). MIT notices are also included in the locally built app.
