# Compact essentials — 0.3.3 (11)

MX Master 4 now places DPI in one row and SmartShift/wheel side by side. SUPERSTRIKE uses one labelled Rapid Trigger picker per button and two columns for profile fields/auxiliary buttons. Protocol, transport, identity, lifecycle, localization and Ring implementation are unchanged. Manual Apply remains required.

Native AppKit/SwiftUI release-source demo fixtures use in-memory preferences, no hardware, updater or login registration. At default 900×500 and minimum 760×500, MX scroll content measured 425.5 points and G HITS 410.5 against a 440-point viewport, in English and Traditional Chinese. No vertical scrolling is needed for those normal-state pages. The G profile component fitted 710×277 including its footer; the installed full profile page also passed the checks below. Warnings, missing permissions, diagnostics expanded or unusual device states may need scrolling.

Eight render variants generated. Default English MX, English minimum, Chinese minimum HITS and Chinese profile component visually inspected; all six scroll-bearing variants passed documentHeight≤viewportHeight. No visual claim based only on a minimum-size constant.

Independent Gemini Argon source review passed with no P1/P2/P3. A bounded follow-up changed only two height constants to 500; exact delta reconstruction and all other source/test hashes were verified, then native renders/metrics repeated. No new broad protocol tests: Core/IO/Support/locales/identity/Ring/tests were byte-identical to the prior verified source.

A release-helper --help capability pipeline incorrectly used grep -q with pipefail, causing a valid tool to be rejected when its stdout was closed early. A 2 MiB help fixture reproduces failure; draining grep succeeds and missing flags still reject. Existing isolated release fixtures passed42/FAIL0. This only changes the packaging script, not the installed app.

## Other models / 開源支援範圍

The GitHub repository was verified public and MIT licensed. Other Logitech generic mouse collections may be listed by macOS name without being opened; names/receivers do not grant configuration support. Not every receiver/paired-device combination can expose a mouse identity. Supported setting paths remain MX Master 4 M and SUPERSTRIKE. CONTRIBUTING.md explains the device evidence needed for adding another model.

## Installed-app acceptance

The same signed/notarized 0.3.3 (11) app was switched through its native Settings to English, safely restarted and returned to Traditional Chinese afterward. Actual Bluetooth MX Master 4 M and USB SUPERSTRIKE were detected in both languages. All six normal pages (MX pointer/scrolling, SUPERSTRIKE HITS and profile/buttons, in both languages) showed no scrollbars or scroll actions and were visually inspected in 1800×1056 screenshots (900×528 window, 900×500 content). The three MX groups and all G profile controls/footer were visible without scrolling.

A local SmartShift threshold draft12→13 enabled Apply; Cancel restored12 and disabled Apply. No hardware Apply was clicked. Login launch, automatic update checks and downloads remained on in both language settings screens; MX automatic mapping restoration stayed off. Device DPI3200 and HITS5/off/3 were read back unchanged. This is UI/draft acceptance, not another physical mouse-button or true Sparkle installation trial.
