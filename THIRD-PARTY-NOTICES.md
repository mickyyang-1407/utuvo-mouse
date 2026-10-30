# Third-party notices

UTUVO Mouse is independent software and is not affiliated with Logitech. No Logitech application, logo or firmware is distributed here.

## Linked runtime package

- Sparkle 2.10.1 (<https://github.com/sparkle-project/Sparkle>), the official update framework. BSD licence; the complete licence, including the external licences of the bundled components (bsdiff, sais-lite, ed25519, SUSignatureVerifier), is in `LICENSES/Sparkle-BSD.txt` and travels inside every build in `Contents/Resources/Sparkle-LICENSE.txt`.

No other third-party runtime package is linked. Apple system frameworks are provided by macOS. See docs/PROTOCOL-SOURCES.md for source links and protocol boundaries.

## Protocol research and implementation references

- m3744/superstrike-macos-cli, commit0158ffb54634b09ea5bcbba9c415ca37c5c0b3bf. Copyright (c) 2026 mclol0. MIT; complete text in LICENSES/mclol0-MIT.txt.
- mclol0/linux-superstrike, commit42588e73b7dc9875e2b6094a7f25081c73b14d0d. Copyright (c) 2026 mclol0. MIT; complete text in LICENSES/mclol0-MIT.txt.
- dpdev69/upright, commitcc76f89b346017739b6ed7620bf27601d141d4ee. Copyright (c) 2026 Upright contributors. MIT; complete text in LICENSES/Upright-MIT.txt.

## Nanostrike
HITS codec, DPI stage codec and format-8 profile layout adapted from [jwake/nanostrike](https://github.com/jwake/nanostrike), Copyright 2026 Justin Wake, MIT. Full notice: LICENSES/Nanostrike-MIT.txt. Source blobs: AnalogButtonRecord f785b9986c1ba3322ad5d194df3f85c05b25d4de; DPIStage 01f59b6281c43d589ae2696138bd9cab479e03f8; ProfileLayout e02ccb5a2a7fe581b62faf2833cb197173313cfd.

## Mouser
macOS Command-C / Command-V event handling cross-checked against [TomBadash/Mouser](https://github.com/TomBadash/Mouser), core/key_simulator.py blob 102dee0dc47b2e912c84f860aa1169d44edc85dd, Copyright (c) 2026 Tom Badash, MIT. Full notice: LICENSES/Mouser-MIT.txt.

DPIGrid.swift additionally adapted from Nanostrike blob d0b87a90fc3dbb8b5e31147bee0965805946e0e8 (MIT, same retained notice).
# Action Ring protocol reference

The MX Master 4 Sense Panel CID 0x01A0 and its temporary-diversion notification
behavior were checked against CommandBloom by Kirill Dubovitskiy (MIT), commit
7ed7b0d8b0904904553c71e6578104ccf8fc3555, PROTOCOL.md and ReprogrammableControlsV4.swift.
https://github.com/bra1nDump/logi-mx-master-gorgeous-action-ring
The app keeps its existing nonexclusive transport and temporary diversion lease;
it does not install upstream daemons or change raw-XY/persistent/remap settings.
License: LICENSES/CommandBloom-MIT.txt. Menu and settings UI are original code.

