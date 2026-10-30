# UTUVO Mouse

A small, independent native macOS controller for Logitech MX Master 4 for Mac and PRO X2 SUPERSTRIKE. English and Traditional Chinese. MIT licensed. No accounts, cloud profiles, RGB editor, macros or preset marketplace.

[Download 0.2.3 beta](https://github.com/mickyyang-1407/utuvo-mouse/releases/tag/v0.2.3) — Developer ID signed, Apple notarized, Gatekeeper accepted.

**0.2.3 beta.** The supported features are implemented and the corrected LIGHTSPEED path has been checked on hardware. See the validation limits below.

## Essentials

| Device | Connection | Controls |
| --- | --- | --- |
| MX Master 4 M | Bluetooth | Battery, DPI, SmartShift, wheel direction/high resolution; middle/back/forward Copy/Paste while the app runs |
| PRO X2 SUPERSTRIKE | USB / LIGHTSPEED | Battery, selected-stage onboard DPI, report rate, middle/back/forward assignments; persistent left/right HITS actuation, Rapid Trigger and haptics |
| App | macOS 14+ | System/English/繁體中文, optional launch at login, explicit MX mapping restore opt-in, optional signed Sparkle updates |

Settings and full profile backups stay on the Mac. Optional update checks contact the public GitHub release feed; system profiling is disabled. Saved preferences describe choices, not proof that the device accepted them. Profile writes require a complete backup and verified readback.

## Use

Keep the app at a stable path before granting Input Monitoring or enabling launch at login. Accessibility is needed for MX Copy/Paste shortcuts. Authentication and permissions stay under macOS control.

Quit the Options+ / G HUB device agents while another app controls the same mouse. This app does not take over button diversion owned by another app. Keep the original utilities for unsupported devices, pairing and firmware updates.

Onboard mode uses settings saved in the mouse. Host mode uses software-managed settings. MX Copy/Paste needs this app running; supported SUPERSTRIKE onboard settings remain in the device. Normal Disable/Quit verifies that owned MX diversion was restored. Disconnects or crashes can require reconnecting the device.

Language changes apply after a safe quit/reopen. Login launch and restoring MX mappings are separate settings, both optional. Automatic update checks/downloads are explicit preferences; the installer waits for safe device cleanup. “Cancel changes” discards an unsaved draft, not an already written profile. Backups: `~/Library/Application Support/UTUVO Mouse/Backups`.

## Build

macOS 14+, Swift 6.2+. Current app binaries target Apple Silicon; Intel/other platforms are unverified. Sparkle 2.10.1 is pinned in `Package.resolved`, and all component notices ship with the app.

```sh
swift test
bash scripts/build.sh
open "build/UTUVO Mouse.app"
```

Development builds use ad-hoc signing and need no release key. Permissions for an ad-hoc rebuild may need refreshing. Production signing uses a stable Developer ID requirement. Only the public update key is in source. See [release instructions](docs/RELEASING.md).

`--probe` reads settings without applying configuration (the receiver can request paired-device announcements). `--demo` shows labelled synthetic data with hardware writes, login registration and updater networking disabled.

## Validation

- 135 isolated tests in 22 suites; independent Gemini review and targeted repair review passed.
- Corrected LIGHTSPEED hardware: actual selected stage and sensor DPI both verified 800 → 3200; only the intended stage bytes/CRC changed. HITS left 6/RT enabled level 3/haptics 4 and right 4/RT enabled level 1/haptics 2 were saved and checked against both NVM and live readback, then the complete daily profile was restored. Final: onboard/profile 1, sensor 3200×3200, both HITS 5/RT off/retained sensitivity 2/haptics 3, auxiliary button records unchanged.
- Earlier USB physical trials confirmed transport, normal left/right clicks, differing haptic strength and a free-form onboard button trial. The corrected USB configuration path now also passed a compound write/readback/restore: sensor 3300×3300, both HITS records, stored report rate 2000 Hz and disabled auxiliary mappings; complete daily profile/control/native auxiliary mappings restored to 3200×3200, HITS 5/RT off/haptics 3 and stored rate 1000 Hz. No new physical press-output counts or actual polling-frequency measurement. No claims about latency, debounce, exact press counts or long-term reliability.
- Production-generated C/V CGEvents passed native AppKit menu dispatch into real NSTextView Copy/Paste. Clipboard restored, no global input posted. This is separate from a physical MX button trial.
- Developer ID update continuity already retained actual MX battery/DPI access without a new permission grant. English/light and Traditional Chinese/dark operator previews covered device panes and Settings. Login registration on/off was checked against macOS; a real next-login launch is unverified.
- Official Sparkle accepted the real signed archive and rejected a one-byte-corrupted copy. Actual HTTPS/Sparkle update 0.2.1 (5) → 0.2.2 (6) downloaded, installed and relaunched successfully. Installed executable matches the published notarized archive; strict signatures/designated requirement, Traditional Chinese preferences and actual MX access were retained without a new grant.

Sensor DPI uses its advertised per-axis grid, including the 20-DPI band at 2000–5000. Off-grid 3250 is rejected before any profile write; the UI steps only through values both axes support. Sleep/disconnect errors remain visible. Unsupported firmware, other models, crash/sleep recovery and new physical press-output counts remain outside the current evidence.

## Open-source foundations

[Nanostrike](https://github.com/jwake/nanostrike) supplies the adapted HITS/DPI codecs and verified format-8 layout. [Mouser](https://github.com/TomBadash/Mouser) supplies the MX/macOS shortcut reference. Both use MIT; copyright notices are retained. [Protocol sources](docs/PROTOCOL-SOURCES.md) record exact source blobs and the corrected RT/DPI interpretation.

Interface direction: [Native – macOS Settings Screens by Daniils](https://dribbble.com/shots/23970985-Native-macOS-Settings-Screens). No reference assets/templates are included.

## 繁體中文

將 MX Master 4 M 與 PRO X2 SUPERSTRIKE 的必要設定放進一個原生 App，提供英文與繁體中文。設定保存在本機，沒有帳號、雲端設定檔、RGB、巨集或預設集商店。

MX 支援電量、DPI、SmartShift、滾輪，以及中鍵／前後側鍵複製貼上；需要 App 持續執行與輔助使用權限。SUPERSTRIKE 支援 USB／LIGHTSPEED、板載 DPI、回報率、輔助按鍵與左右 HITS。登入啟動、MX 自動還原、自動更新可分別選擇。

本次無線實機已確認真正生效的 3200 DPI、HITS 的儲存與開關位元，並在測後完整還原 5／關閉／3，保留板載模式與 3200 DPI。新版 USB 已通過 DPI、HITS、回報率資料及側鍵設定的寫入／讀回／完整還原，並驗證不合法 DPI 在寫入前拒絕；沒有要求使用者重新試按。先前 USB 實體試按與本次設定路徑讀寫結果分別記錄，不宣稱精確點擊數、延遲或長期穩定性。已通過 135 項隔離測試、獨立程式審查與原生文字框複製貼上整合測試。

使用時先退出同時控制滑鼠的原廠裝置代理；本 App 不修改韌體、不接管別人的按鍵改道，也不代替你授予系統權限。更新簽章與損毀檔拒絕已通過；App 已從真正的 HTTPS 來源完成 0.2.1 (5) → 0.2.2 (6) 下載、安裝與重啟，確認簽章、繁中設定與 MX 實際存取保留，不需重新授權。登入註冊已驗證，下次真實登入仍待確認。

## License

MIT. See `LICENSE`, `THIRD-PARTY-NOTICES.md` and `LICENSES/`. Logitech trademarks and product names belong to their owners. This project is not affiliated with Logitech.
