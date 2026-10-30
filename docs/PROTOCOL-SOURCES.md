# Protocol sources

- [Nanostrike](https://github.com/jwake/nanostrike), MIT, Copyright 2026 Justin Wake. Adapted `AnalogButtonRecord.swift` blob f785b9986c1ba3322ad5d194df3f85c05b25d4de and `DPIStage.swift` blob 01f59b6281c43d589ae2696138bd9cab479e03f8. Verified format-8 layout from `ProfileLayout.swift` blob e02ccb5a2a7fe581b62faf2833cb197173313cfd and current sensor-parameter implementation. Full notice in `LICENSES/Nanostrike-MIT.txt`.
- [Mouser](https://github.com/TomBadash/Mouser), MIT, Copyright (c) 2026 Tom Badash. MX Master 4 reporting and macOS shortcut handling cross-check; `core/key_simulator.py` blob 102dee0dc47b2e912c84f860aa1169d44edc85dd and `core/hid_gesture.py` blob 5c0b1479e1ac4a97f702eb3d6ef9f9c7a8066104. Full notice in `LICENSES/Mouser-MIT.txt`.
- [superstrike-macos-cli](https://github.com/m3744/superstrike-macos-cli/tree/0158ffb54634b09ea5bcbba9c415ca37c5c0b3bf), MIT; earlier onboard/transport research. Its literal-zero Rapid Trigger Off interpretation is superseded by Nanostrike's verified independent enable bit.
- [linux-superstrike](https://github.com/mclol0/linux-superstrike/tree/42588e73b7dc9875e2b6094a7f25081c73b14d0d), MIT, protocol comparison.
- [upright](https://github.com/dpdev69/upright/tree/cc76f89b346017739b6ed7620bf27601d141d4ee), MIT, IOKit HID transport research.
- [Solaar](https://github.com/pwr-Solaar/Solaar), GPL-2.0-or-later, protocol research only. No Solaar code/package is included or relicensed.

## Verified layout corrections

HITS sensitivity is 1–5 in bits 7–2; bit 0 independently enables Rapid Trigger. `14 08 0C` means actuation 5, RT disabled with retained sensitivity 2, haptics 3. Off clears bit 0; sending a zero sensitivity is invalid. Live HITS is volatile; persistent settings use two 3-byte records at 0x26 in the format-8, 255-byte profile. Reserved bits come from each record's own storage, not a live reply.

The DPI table starts at 0x04: five 5-byte records (little-endian X, Y, lift-off). Default index is byte 2; live index is 0x8100 fn0B. Bytes 9–12 describe stage 1, not a universal active DPI. Sensor fn5 reports current-X/default-X/current-Y/default-Y, big-endian. A DPI apply verifies both the full stored profile and the sensor values.

Feature indexes are discovered. Profile format, counts, CRC and current state are guarded before writes. A protocol ACK is not physical proof. No firmware or manufacturer app is distributed.
