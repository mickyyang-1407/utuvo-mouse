# UTUVO Mouse

> **Unofficial personal project.** Not made, endorsed or supported by Logitech. Logitech G HUB and Logi Options+ remain the reference for every feature and setting; this app only covers a few everyday controls for the owner's own mice.
>
> **個人自用的非官方工具。** 不是羅技製作、背書或支援的產品；所有功能與設定以羅技官方 G HUB／Logi Options+ 為準，這裡只整合幾個日常會用到的開關。

A small, independent native macOS controller for Logitech MX Master 4 for Mac and PRO X2 SUPERSTRIKE. English and Traditional Chinese. MIT licensed. No accounts, cloud profiles, RGB editor, macros or preset marketplace.

[Download 0.5.2 beta](https://github.com/mickyyang-1407/utuvo-mouse/releases/tag/v0.5.2) — Developer ID signed, Apple notarized, Gatekeeper accepted.

**0.5.2 beta.** The supported features are implemented and the corrected LIGHTSPEED path has been checked on hardware. See the validation limits below.

## Essentials

| Device | Connection | Controls |
| --- | --- | --- |
| MX Master 4 M | Bluetooth | Battery, DPI, SmartShift, wheel direction/high resolution; middle/back/forward Copy/Paste and an editable eight-position Action Ring while the app runs |
| PRO X2 SUPERSTRIKE | USB / LIGHTSPEED | Battery, selected-stage onboard DPI, report rate, middle/back/forward assignments; persistent left/right HITS actuation, Rapid Trigger and haptics |
| App | macOS 14+ | System/English/繁體中文, optional launch at login, explicit MX mapping restore opt-in, optional signed Sparkle updates |

Settings and full profile backups stay on the Mac. Optional update checks contact the public GitHub release feed; system profiling is disabled. Saved preferences describe choices, not proof that the device accepted them. Profile writes require a complete backup and verified readback.

## Use

Keep the app at a stable path before granting Input Monitoring or enabling launch at login. Accessibility is needed for MX Copy/Paste shortcuts. Authentication and permissions stay under macOS control.

Quit the Options+ / G HUB device agents while another app controls the same mouse. This app does not take over button diversion owned by another app. Keep the original utilities for unsupported devices, pairing and firmware updates.

Onboard mode uses settings saved in the mouse. Host mode uses software-managed settings. MX Copy/Paste needs this app running; supported SUPERSTRIKE onboard settings remain in the device. Normal Disable/Quit verifies that owned MX diversion was restored. Disconnects or crashes can require reconnecting the device.

Language changes apply after a safe quit/reopen. Login launch and restoring MX mappings are separate settings, both optional. Automatic update checks/downloads are explicit preferences; the installer waits for safe device cleanup. “Cancel changes” discards an unsaved draft, not an already written profile. Backups: `~/Library/Application Support/UTUVO Mouse/Backups`.

## Automatic identification

Exact product IDs identify MX Master 4 M and USB SUPERSTRIKE. A LIGHTSPEED receiver requires its paired device’s reported name; shared DPI/onboard features never establish a model. Other Logitech mouse collections appear by their macOS-reported name, with a read-only notice and no configuration controls or device opening. [Identification details](docs/IDENTIFICATION.md).

0.5.2: lighter seams and buttons on light-colored MX drawings, and a clearer note that this is an unofficial personal tool.

0.5.1: a mouse that wakes up behind a LIGHTSPEED receiver now appears without pressing Refresh. A supported mouse whose first read was incomplete is read again too. The app listens for the receiver's link notification and, only while a receiver has no reachable mouse or a read was incomplete, reads again every 30 seconds.

0.5.0 adds a menu bar icon (it can be turned off in Settings) with each mouse, its battery and quick Profile switching. PRO X2 SUPERSTRIKE switches between the onboard profiles the mouse reports; each switch is read back to confirm. MX Master 4 M has no onboard profiles, so its profiles are saved in the app (DPI, SmartShift, wheel): saving sends nothing, and switching sends only the values that differ, then reads the mouse back. A check mark only appears when the mouse reports those values. Nothing switches automatically.

0.4.0 redesigned the window: a translucent sidebar with a color tile and battery level per mouse, a large battery read-out with a charge bar (solid is charge left, striped is used; an unreported level stays fully striped instead of being guessed), one status card (read back from the mouse / permission needed / write unconfirmed / read-only model), pill tabs and a floating bar with Refresh. Device protocol, settings and preferences are unchanged. Because of the larger header, settings below it now scroll at the default window size.

0.3.3 put MX DPI in one row, with SmartShift and wheel controls side by side. SUPERSTRIKE has compact HITS controls and two columns for profile fields/buttons. Normal settings fit without scrolling in a 900 × 500 content area (760 × 500 minimum). English, Traditional Chinese, light/dark appearance and existing login/update preferences remain available. Expanded diagnostics, permission warnings or unusual device states may need scrolling. See [compact-layout validation](docs/COMPACT-UI.md).

## Action Ring

Select MX Master 4 → Action Ring. Click a position and choose its action; the eight-position layout saves locally. Preview never executes shortcuts. Enable the haptic thumb button after Options+ releases it. Hold the thumb button, move toward an action and release; release in the center or press Esc to cancel. Actions include Copy, Paste, Cut, Undo, Redo, Select all, Finder, Spotlight, Screenshot and Mission Control, using standard macOS shortcut bindings.

This app owns the overlay; it does not modify Options+ profiles. Keep UTUVO Mouse running with its existing Accessibility/Input Monitoring grants. Enablement and layout are separate: automatic mapping restoration remains an explicit Settings opt-in. Foreign ownership is refused. Disable/Quit verifies restoration of temporary diversion. Hardware configuration enable/readback/disable passed on the actual Bluetooth MX; physical press/selection acceptance is not claimed by synthetic tests.

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

- Prior Core/IO/support gate: 141 isolated tests in 24 suites. The identification update passed 21 focused tests in 3 suites, including 5 new identity/parser tests. 0.3.3 adds native viewport, actual bilingual page and local draft/cancel checks; no protocol behavior was changed. Independent Gemini reviews passed.
- Corrected LIGHTSPEED hardware: actual selected stage and sensor DPI both verified 800 → 3200; only the intended stage bytes/CRC changed. HITS left 6/RT enabled level 3/haptics 4 and right 4/RT enabled level 1/haptics 2 were saved and checked against both NVM and live readback, then the complete daily profile was restored. Final: onboard/profile 1, sensor 3200×3200, both HITS 5/RT off/retained sensitivity 2/haptics 3, auxiliary button records unchanged.
- Earlier USB physical trials confirmed transport, normal left/right clicks, differing haptic strength and a free-form onboard button trial. The corrected USB configuration path now also passed a compound write/readback/restore: sensor 3300×3300, both HITS records, stored report rate 2000 Hz and disabled auxiliary mappings; complete daily profile/control/native auxiliary mappings restored to 3200×3200, HITS 5/RT off/haptics 3 and stored rate 1000 Hz. No new physical press-output counts or actual polling-frequency measurement. No claims about latency, debounce, exact press counts or long-term reliability.
- Production-generated C/V CGEvents passed native AppKit menu dispatch into real NSTextView Copy/Paste. Clipboard restored, no global input posted. This is separate from a physical MX button trial.
- Developer ID update continuity already retained actual MX battery/DPI access without a new permission grant. English/light and Traditional Chinese/dark operator previews covered device panes and Settings. Login registration on/off was checked against macOS; a real next-login launch is unverified.
- The local 0.2.2 (6) → 0.2.3 (7) HTTPS/Sparkle update also installed and relaunched successfully with login launch, automatic checks and automatic downloads enabled and retained. The native USB stepper offered 3200 → 3220, and cancelling the draft retained actual 3200 DPI.
- Official Sparkle accepted the real signed archive and rejected a one-byte-corrupted copy. Actual HTTPS/Sparkle update 0.2.1 (5) → 0.2.2 (6) downloaded, installed and relaunched successfully. Installed executable matches the published notarized archive; strict signatures/designated requirement, Traditional Chinese preferences and actual MX access were retained without a new grant.

Sensor DPI uses its advertised per-axis grid, including the 20-DPI band at 2000–5000. Off-grid 3250 is rejected before any profile write; the UI steps only through values both axes support. Sleep/disconnect errors remain visible. Unsupported firmware, other models, crash/sleep recovery and new physical press-output counts remain outside the current evidence.

## Resource use

0.3.1 replaces the Action Ring’s 60 Hz pointer polling with native AppKit tracking events and a single timeout. Identical isolated native HUD tests measured idle CPU at 0.370% → 0.00574% of one core and interrupt wakeups at 60.47 → 0.50 per second. Sixty open/cancel cycles left no retained panels in either version; this is a polling optimization, not a claimed memory-leak fix. See [measurement conditions and whole-app results](docs/PERFORMANCE.md).

## Open-source foundations

[Nanostrike](https://github.com/jwake/nanostrike) supplies the adapted HITS/DPI codecs and verified format-8 layout. [Mouser](https://github.com/TomBadash/Mouser) supplies the MX/macOS shortcut reference. Both use MIT; copyright notices are retained. [Protocol sources](docs/PROTOCOL-SOURCES.md) record exact source blobs and the corrected RT/DPI interpretation.

MX Master 4 Sense Panel behavior was checked against [CommandBloom](https://github.com/bra1nDump/logi-mx-master-gorgeous-action-ring), MIT, commit `7ed7b0d8b0904904553c71e6578104ccf8fc3555`. Its license is retained. The ring and settings use original SwiftUI/AppKit code; no upstream daemons are installed.

Design references: [Mouse setup application by Webbbin](https://dribbble.com/shots/20256015-Mouse-setup-application), [Mouse Controller by Netro Systems](https://dribbble.com/shots/20848919-Desktop-App-UI-Design-Mouse-Controller), and [Native macOS Settings by Daniils](https://dribbble.com/shots/23970985-Native-macOS-Settings-Screens). Device artwork and UI are original; no reference assets/templates are included.

## 繁體中文

將 MX Master 4 M 與 PRO X2 SUPERSTRIKE 的必要設定放進一個原生 App，提供英文與繁體中文。設定保存在本機，沒有帳號、雲端設定檔、RGB、巨集或預設集商店。

MX 支援電量、DPI、SmartShift、滾輪、中鍵／前後側鍵複製貼上，以及可配置八個位置的 Action Ring；需要 App 持續執行與輔助使用權限。SUPERSTRIKE 支援 USB／LIGHTSPEED、板載 DPI、回報率、輔助按鍵與左右 HITS。登入啟動、MX 自動還原、自動更新可分別選擇。

本次無線實機已確認真正生效的 3200 DPI、HITS 的儲存與開關位元，並在測後完整還原 5／關閉／3，保留板載模式與 3200 DPI。新版 USB 已通過 DPI、HITS、回報率資料及側鍵設定的寫入／讀回／完整還原，並驗證不合法 DPI 在寫入前拒絕；沒有要求使用者重新試按。先前 USB 實體試按與本次設定路徑讀寫結果分別記錄，不宣稱精確點擊數、延遲或長期穩定性。已通過 141 項隔離測試、獨立程式審查與原生文字框複製貼上整合測試。

使用時先退出同時控制滑鼠的原廠裝置代理；本 App 不修改韌體、不接管別人的按鍵改道，也不代替你授予系統權限。更新簽章與損毀檔拒絕已通過；App 已從真正的 HTTPS 來源完成 0.2.1 (5) → 0.2.2 (6) 下載、安裝與重啟，確認簽章、繁中設定與 MX 實際存取保留，不需重新授權。登入註冊已驗證，下次真實登入仍待確認。

新版以裝置示意圖、分頁與一致的控制層次重新設計，保留英文／繁中與深淺色。在「MX Master 4 → Action Ring」點選八個位置來指定動作；按住拇指鍵、移向動作後放開，中央放開或 Esc 可取消。配置儲存在本機，不修改 Options+ 設定檔。原廠代理須先釋放拇指鍵，且 UTUVO Mouse 須持續執行；下次啟動是否恢復按鍵，仍由設定中的明確選項控制。實際藍牙裝置已通過啟用讀回／停用還原；隔離模擬按鍵測試不冒充實體拇指按壓驗收。

0.3.1 將 Action Ring 每秒 60 次的游標輪詢改成 AppKit 原生滑鼠事件。相同隔離原生測試的靜止 CPU 從單核心 0.370% 降至 0.00574%，每秒中斷喚醒從 60.47 降至 0.50；反覆開關 60 次，兩版都沒有殘留視窗。完整 App 與隔離浮層的耗用分開記錄，詳見[資源量測](docs/PERFORMANCE.md)。

0.5.1：LIGHTSPEED 接收器後面的滑鼠醒來時，不用按「重新整理」就會出現。讀取不完整的滑鼠也會自動重讀。App 會聽接收器的連線通知，而且只在「有接收器但連不到滑鼠」或「讀取不完整」時每 30 秒再讀一次。

0.5.0 新增選單列 icon（可在設定關掉）：列出每支滑鼠、電量，並可快速切換 Profile。PRO X2 SUPERSTRIKE 切換滑鼠回報的板載 Profile，每次都讀回確認；MX Master 4 M 沒有板載 Profile，所以 Profile 存在 App 裡（DPI、SmartShift、滾輪）：儲存不會送任何東西，切換只送出不同的值再讀回。只有滑鼠回報的值相符才打勾；不會自動切換。

0.4.0 重新設計視窗：半透明側欄、每支滑鼠的色塊 icon 與電量；大字電量與電量條（實心＝剩餘、斜線＝已用，沒回報就整條斜線、不猜數字）；一張狀態卡（數值讀自滑鼠／需權限／寫入未確認／只讀型號）；膠囊分頁與底部浮動列。裝置通訊、設定與偏好都沒改；因頁首變大，預設視窗下方設定需要捲動。

0.3.3 將 MX 的 DPI 排成單列、SmartShift 與滾輪左右並排，SUPERSTRIKE 的板載設定與按鍵也分兩欄。一般設定在 900×500 內容區即可看完，最小尺寸 760×500；展開診斷、權限或特殊狀態可能需要捲動。MX Master 4 M／USB SUPERSTRIKE 依產品 ID 自動辨識，LIGHTSPEED 依接收器回報的配對裝置名稱確認；不再靠通用功能猜型號。其他 Logitech 滑鼠可顯示系統回報名稱，僅提供辨識、不開啟或設定裝置。中英文、登入自啟動與自動更新偏好均保留。

## Contributing

Other Logitech mouse names can appear through passive macOS inventory; settings support is currently limited to the two verified models. Not every receiver/pairing combination can expose a mouse name. To help add a model, see [CONTRIBUTING.md](CONTRIBUTING.md) for the required protocol and isolated/hardware evidence.

## License

MIT. See `LICENSE`, `THIRD-PARTY-NOTICES.md` and `LICENSES/`. Logitech, Logi, G HUB, Logi Options+, MX Master, PRO X2 SUPERSTRIKE and other product names are trademarks of Logitech; they are used only to say which mice this app works with. This project is not affiliated with Logitech and uses no Logitech logos, software or firmware. The mouse drawings are original illustrations used to identify a connected mouse. The protocol work relies on publicly documented HID++ research from open-source projects (Solaar, libratbag) and on reading the owner's own devices.
