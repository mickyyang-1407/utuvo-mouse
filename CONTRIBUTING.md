# Contributing

UTUVO Mouse is MIT licensed. Build instructions, supported devices and validation limits are in README. UI changes should preserve English and Traditional Chinese and work at the documented minimum window size.

## Adding a mouse model

Detection and configuration support are separate. Other Logitech mouse collections can appear by their macOS-reported name without being opened. This does not establish a known profile format or permission to configure them. Receivers may expose only the receiver name; not every receiver/pairing combination is identified.

For a model request, include the model name, USB/Bluetooth/receiver connection, macOS version, app version, public USB vendor/product IDs if available, and the problem. Review reports before posting. Do not include serial numbers, Bluetooth addresses, private backups, keys or unedited system dumps.

A device-support PR should include exact product/paired identity, primary protocol references and their licenses, isolated byte fixtures, negative/stale/timeout coverage, per-model format and capability checks, backup/readback behavior, and clear hardware validation evidence. Do not enable writes by matching a friendly name or common feature alone. Keep new devices read-only until the supported path is verified. Do not claim physical behavior based only on acknowledgments or mock tests.

Changes to CRC-sensitive onboard layouts must preserve unknown bytes and existing settings; unknown firmware/layouts must fail closed. Do not add vendor daemons, global input capture, accounts, telemetry, profile marketplaces or dependencies without a concrete need.

## 繁體中文

歡迎回報與提交其他滑鼠的支援。能顯示名稱不代表可以安全套用 DPI、HITS 或板載格式；經接收器連接時，也不保證每個型號都能辨識。回報請附型號、連線方式、macOS/App 版本與公開 VID/PID，勿附序號、藍牙位址、私有備份或未整理的系統資訊。

新增控制前需要該型號的協定來源、隔離測試及實機讀回證據；未驗證的型號保持僅辨識。英文／繁中必須同步，UI 需在最小視窗下保持可用。
