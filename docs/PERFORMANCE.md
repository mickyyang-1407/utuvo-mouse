# Resource use — 0.3.1 (9)

Measured on 2026-10-30 on one Apple Silicon Mac running macOS. These are short samples, not battery-life, latency or long-term reliability claims. CPU percentages are fractions of one core; memory is physical footprint, not RSS. No hardware settings, vendor agents or permissions were changed for these measurements.

## Installed whole app

The Developer ID signed, notarized app ran from its normal stable installation path. SUPERSTRIKE was connected by USB; MX was offline and Action Ring disabled. Launch at login, automatic update checks and automatic downloads remained on. MX mapping restoration remained off. Device discovery completed before sampling. Background means both app windows closed while the app kept running.

| Scenario | Duration | Average CPU, one core | Physical footprint, start → end (peak) | Interrupt wakeups/s | Disk reads/writes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0.3.0, device page idle | 30 s | 0.00188% | 79.89 → 79.85 MiB (79.91) | 0.067 | 0 / 0 bytes |
| 0.3.0, one Refresh included | 15 s | 0.83580% | 79.94 → 66.92 MiB (79.97) | 1.466 | 0 / 0 bytes |
| 0.3.1, device page idle after relaunch/settings inspection | 30 s | 0.03791% | 55.81 → 68.13 MiB (68.14) | 0.233 | 0 / 0 bytes |
| 0.3.1, windows closed, background idle | 30 s | 0.00520% | 54.03 → 53.83 MiB (54.03) | 0.167 | 0 / 0 bytes |

Package-idle wakeup counters and logical writes did not increase in these samples. Different cache/startup/window states make the whole-app rows unsuitable for claiming a CPU or memory percentage improvement. In particular, the lower post-relaunch footprint is not evidence that this patch fixed a memory leak. The background result does not measure active MX button diversion or physical Action Ring interaction.

## Action Ring comparison

The actual app source was compiled in release mode into an isolated native AppKit fixture for each version. The fixture used the same frozen Core/IO/Support/localization code, demo mode, no HID handles, no shortcut output, no settings persistence, no updater and no login registration. An asynchronous scenario ran under `NSApplication.run`, matching the native main event loop. Its panel was moved offscreen immediately; measurements isolate idle controller work and exclude visible WindowServer compositing. This is not a whole-app memory result or physical thumb-button acceptance.

| Ring held open with no pointer movement | 0.3.0 | 0.3.1 |
| --- | ---: | ---: |
| Sample duration | 10.005 s | 10.008 s |
| CPU, one core | 0.37018% | 0.00574% |
| Interrupt wakeups/s | 60.47 | 0.50 |
| Disk reads/writes | 0 / 0 bytes | 0 / 0 bytes |

The change removes the repeating 60 Hz timer, its repeated actor tasks, cursor reads and frontmost-app queries. Native AppKit tracking handles movement, drag movement and exit. A workspace notification handles application changes. One cancelable 15-second deadline replaces repeated timeout checks. Selection changes update the view only when the selected slot changes; release and click still verify their target application.

Both versions completed 60 open/cancel cycles with zero retained panels and zero remaining app windows. No continuing footprint growth was observed during the short settle samples. Native synthetic events checked coordinate conversion, drag-enabled tracking, top/right selection and exit cancellation. A canceled deadline did not close a later presentation, and the later presentation timed out correctly. Independent Gemini review passed; a subsequent single tracking-area drag option was checked as a bounded follow-up. These tests do not replace a physical MX thumb-button trial.

## Method

The read-only sampler uses `proc_pid_rusage` (version 4) on the app's own PID, checks process start time, and subtracts cumulative CPU, interrupt/package wakeup and disk/logical-write counters. On this Mac the CPU counters use Mach ticks: `mach_timebase_info` was 125/3 ns per tick. This was independently calibrated against a CPU-bound loop and `getrusage`; raw counters are not assumed to be nanoseconds. Physical footprint samples use `ri_phys_footprint`; RSS includes a different set of pages and is not interchangeable.

A first fixture used a nested synchronous run loop and could starve main-actor deadline tasks. It was discarded and replaced with the native asynchronous application-delegate scenario before the final comparison and timeout checks. Only the corrected results are reported above.

## 繁體中文

0.3.1 的正式 App 在關閉視窗、保持背景執行的 30 秒實測中，平均 CPU 為單核心 0.00520%，實際記憶體約 54 MiB，磁碟讀寫 0 bytes。登入自啟動、自動檢查與自動下載均保持開啟。此時 USB SUPERSTRIKE 在線，MX 離線；不代表啟用 MX 按鍵改道時的耗用。

Action Ring 改用原生滑鼠事件與單次超時，取消每秒 60 次輪詢。相同隔離原生浮層的靜止測試，CPU 由 0.37018% 降至 0.00574%，每秒中斷喚醒由 60.47 降至 0.50。元件測試不包含可見浮層的 WindowServer 合成成本，也不冒充實體拇指按壓測試。兩版反覆開關 60 次都沒有殘留視窗；本次沒有發現或宣稱修復記憶體洩漏。量測時間較短，不等於長期穩定性或電池續航驗證。
