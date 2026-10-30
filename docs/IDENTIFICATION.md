# Mouse identification — 0.3.2

Model identity and configuration support are separate. Devices are listed automatically; choosing a device shows only its corresponding controls.

| Device | Identification | Configuration |
| --- | --- | --- |
| MX Master 4 M for Mac | Logitech 046D:B042 | Existing Bluetooth MX controls, including Action Ring |
| PRO X2 SUPERSTRIKE, USB | Logitech 046D:C0A8 | Existing onboard/HITS controls |
| PRO X2 SUPERSTRIKE, LIGHTSPEED | Receiver 046D:C54D plus complete paired DEVICE_NAME reply matching PRO X2 SUPERSTRIKE | Existing supported SUPERSTRIKE path; a receiver alone is not a mouse identity |
| Other Logitech mouse collections | macOS registry-reported product name | Display only; these collections are never opened or probed |

Common onboard, DPI or scrolling features cannot establish a model. Unknown names, invalid UTF-8, incomplete replies and unverified receiver identities do not enable controls. A verified paired name for another model remains read-only. Device-name reads use HID++ feature 0x0005: function 0 returns the byte length; function 1 reads fragments at a byte offset. Reads are bounded to 128 bytes and reject control characters. Protocol facts were consulted from [Solaar’s primary implementation](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py); no GPL implementation was copied.

Passive inventory matches only Logitech generic mouse collections (usage page 1, usage 2). Matching reads registry metadata without opening the device or registering input handlers. Existing supported interfaces retain the allowlist, non-seizing open and cleanup behavior. Multiple known interfaces share one identity; removal of a sibling collection cannot close the active transport.

Five new isolated tests cover exact direct IDs, wrong vendors, receiver names, false model inference from common features, naming/presentation and bounded multi-frame name parsing. Focused identity, localization and snapshot-completeness regression: 21 tests in 3 suites passed. Independent Gemini source review passed. Nine native demo layout renders cover both locales, light/dark, 760×560 minimum, unsupported devices and the sidebar permission warning. The permission banner is intentionally suppressed in demo mode and is not claimed as a new permission-flow test.

The installed 0.3.2 app actually displayed MX Master 4 M over Bluetooth (100%, 3200 DPI) and SUPERSTRIKE over USB (100%, both HITS 5/RT off/haptics 3). No hardware configuration was written in this UI/identification pass. This pass did not repeat a wireless physical trial, next-login launch or end-to-end updater installation; earlier validation remains documented separately in README.

## 繁體中文

MX Master 4 M 和 USB SUPERSTRIKE 用明確的產品 ID 辨識；LIGHTSPEED 必須讀到完整配對滑鼠名稱。接收器在線或具備板載／DPI 功能，都不等於確認了滑鼠型號。其他 Logitech 滑鼠顯示 macOS 回報的名稱，標示「僅辨識」，不開啟、不攔截輸入，也不提供未支援的設定。

新版已在實際 App 同時顯示藍牙 MX Master 4 M 和 USB SUPERSTRIKE。中英文、深淺色、登入自啟動與自動更新偏好均保留；本次不改滑鼠設定、不要求重新授權或重複試按。
