# UTUVO Mouse

A small native macOS app for the essential controls of Logitech MX Master 4 for Mac and PRO X2 SUPERSTRIKE. English and Traditional Chinese. No account, cloud profiles, RGB editor, macros or preset marketplace. Independent software, not affiliated with Logitech.

> Local open-source preparation — not yet published. Corrected 0.2.1 (5) is signed and installed locally; current SUPERSTRIKE hardware, next-login launch and real-update acceptance remain pending.

## Essential controls

| Device | Controls |
| --- | --- |
| Both | Actual connection and battery state |
| MX Master 4 M, Bluetooth | DPI, SmartShift, wheel direction/high resolution; middle/back/forward mapped to Copy or Paste while the app runs |
| PRO X2 SUPERSTRIKE, USB / LIGHTSPEED | Persistent left/right HITS actuation, Rapid Trigger and haptics; selected-stage onboard DPI, report rate and auxiliary button assignments |
| App | System/English/繁體中文; optional launch at login; saved MX mapping choices with explicit automatic-restore opt-in; optional signed updates |

The current candidate has not completed end-to-end hardware and signed-update acceptance. Settings and backups stay on the Mac. Optional update checks contact the public GitHub release feed; system profiling is disabled. Saved preferences describe your choices, not proof that hardware accepted them. Device writes use verified reads and preserve uncertain results instead of inventing a successful state.

## Use

Install the signed release at a stable location before enabling launch at login. Grant Input Monitoring if macOS denies the MX Bluetooth interface, and Accessibility for Copy/Paste shortcuts. Confirm system authentication yourself. The app does not grant its own permissions or use a privileged helper.

Quit the Options+ and G HUB device agents while controlling the same mouse, since they can change settings and own button diversion. A button owned by another app is not taken over automatically. Keep the original vendor apps available for unsupported devices, receiver pairing and firmware updates.

G HUB host mode uses software-managed profiles. Onboard mode uses the supported profile saved in the mouse, so its DPI/button assignments can keep working with the controller closed. This app shows a warning when the stored profile is not active. MX Copy/Paste mapping requires this app to stay running. Normal disable/quit is designed to verify restoration; disconnects or crashes may require reconnecting or power cycling the mouse.

Language changes apply after a safe quit and reopen. Launch at login and restoring previously enabled MX mappings are separate choices. The updater verifies signatures, and waits for safe device cleanup before handing control to its installer. Automatic checks and downloads are explicit preferences.

“Cancel changes” discards an unsaved draft. It does not roll back a saved flash backup. Backups are under `~/Library/Application Support/UTUVO Mouse/Backups`, with temporary mapping leases under `Diversions`.

## Build

macOS 14+, Swift 6.2+. Sparkle is pinned in `Package.resolved`; all required notices ship with the app. Current produced app architecture is Apple Silicon. Intel and other operating systems require their own validation.

```sh
swift test
bash scripts/build.sh
open "build/UTUVO Mouse.app"
```

Development builds are ad-hoc signed and need no release key. Their updater stays disabled when release configuration is absent. Rebuilding an ad-hoc app can require granting permissions again. Release signing and updater keys are separate; only the update public key (`config/updater-public-key.txt`) belongs in source. See [release instructions](docs/RELEASING.md) for protected local signing.

`--probe` reads device state without applying settings. `--demo` shows synthetic data with device writes, login registration and updater networking disabled. Neither is evidence of physical button output.

## Validation boundaries

The corrected source passes 128 isolated tests in 21 suites. English/light and Traditional Chinese/dark operator previews cover both device panes, diagnostics and Settings. In the signed local 0.2.0 (4) candidate, Traditional Chinese was saved and applied after a safe quit/reopen, and macOS login registration returned enabled. The corrected local 0.2.1 (5) was installed with the same Developer ID requirement and reads MX battery/DPI without a new grant. Production-generated CGEvents passed native AppKit key-equivalent dispatch into real NSTextView Copy/Paste, with the clipboard restored and no global events posted. This is separate from physical button input. Current SUPERSTRIKE hardware, next-login launch and signed update installation remain pending. Registration is distinct from a real next-login launch; configuration alone does not prove installation.

Earlier 0.1.0 (2) physical evidence: MX and SUPERSTRIKE DPI round trips; different left/right SUPERSTRIKE HITS settings with human confirmation of normal clicks and stronger left haptics; a free-form onboard Copy/Paste trial with the controller closed. Original HITS replies and the approved complete onboard profile/control sectors were read back after restoration. The earlier free-form trial did not validate the later MX keycode implementation; it is now corrected to ANSI C=8 and V=9 and tested against the actual generated CGEvents. These trials do not measure exact press counts, error rates, latency, debounce or long-term reliability.

Rapid Trigger has an independent enable bit: retained sensitivity 2 with bit 0 cleared means Off. The correction adapts the MIT-licensed Nanostrike HITS/DPI codecs and cross-checks MX shortcuts with Mouser. DPI now follows the selected stage and verifies sensor values; earlier fixed-stage checks did not establish the active DPI. LIGHTSPEED and USB are both required. Earlier wireless actuation/haptic changes were confirmed on hardware; true RT enable and the corrected persistent/selected-stage paths still lack fresh hardware acceptance. A sleeping/unreachable receiver is reported as unavailable, rather than mislabelled BUSY. Sleep/wake, crash recovery, other devices/firmware and long-term use must not be described as accepted without evidence.

## 繁體中文

把 MX Master 4 M 與 PRO X2 SUPERSTRIKE 的必要設定放在一個原生 App，提供英文與繁體中文。沒有帳號、雲端設定檔、RGB 編輯器、巨集或預設集商店。設定保存在本機；選擇啟用更新檢查後，才會連到公開的 GitHub 更新來源，不回傳系統分析資料。

登入啟動、還原上次啟用的 MX 按鍵設定、自動更新都可分別選擇。MX 複製／貼上需要 App 持續執行及輔助使用權限；G 板載設定則可保留在滑鼠上。使用前先退出同時控制該滑鼠的原廠裝置代理。輸入監控、輔助使用及系統驗證由你在 macOS 允許。切換語言後，安全結束並重新開啟 App 即可套用。

目前修正版通過 128 項隔離測試與程式碼複查，尚未公開。修正版 0.2.1 (5) 已用相同憑證識別安裝，MX 可正常讀取且不需重新授權；原生 AppKit／NSTextView 複製貼上整合測試通過，剪貼簿已還原，沒有傳送全域輸入事件。已簽章的本機 0.2.0 (4) 確認繁中設定可保存並在重開套用，登入項目可向 macOS 註冊。正式公開前仍需完成 USB／LIGHTSPEED 與 MX 實體按鍵、下次登入啟動及實際更新結果；已完成的 HITS 與 G 側鍵自由按壓不代表精確次數或長期可靠度測試。Logitech 商標與產品名稱屬原權利人，本專案與 Logitech 無隸屬關係。

Interface direction: [Native – macOS Settings Screens by Daniils](https://dribbble.com/shots/23970985-Native-macOS-Settings-Screens). Reference assets and template code are not included.

## Open-source foundations

[Nanostrike](https://github.com/jwake/nanostrike) supplies adapted HITS/DPI codecs and verified format-8 layout. [Mouser](https://github.com/TomBadash/Mouser) supplies the MX/macOS shortcut reference. Both are MIT licensed; notices are retained.

## License

MIT. See `LICENSE`, `THIRD-PARTY-NOTICES.md`, `LICENSES/` and `docs/PROTOCOL-SOURCES.md`. Sparkle's complete bundled component notices are included.
