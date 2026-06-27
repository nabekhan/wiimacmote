# Third-party notices

## Wiiuse

The Wii Remote protocol, extension identity, MotionPlus capability, and expansion parser behavior in `WiimoteProtocol.swift` and `WiimoteHIDController.swift` include Swift adaptations of concepts and constants from Wiiuse:

- Project: Wiiuse
- Repository: https://github.com/wiiuse/wiiuse
- Primary original author: Michael Laforest
- Additional MotionPlus authors credited by Wiiuse: Michal Wiedenbauer, Dave Murphy, Hector Martin, and Radu Andries
- TaTaCon support credited by Wiiuse to pixelomer
- License: GPL-3.0-or-later

This project ports selected behavior from Wiiuse's `wiiuse.h`, `wiiuse_internal.h`, `events.c`, `wiiuse.c`, `io.c`, `motion_plus.c`, `guitar_hero_3.c`, `nunchuk.c`, `classic.c`, and `tatacon.c` into Swift while keeping WiiMacMote's macOS HID/Bluetooth transport separate. Because this code is derived from GPL-licensed Wiiuse behavior, WiiMacMote distributions that include it must satisfy GPL-3.0-or-later obligations. See `LICENSE`.

## WaveBird

The Xbox Series and Switch Pro virtual presentation work in `VirtualGamepadReports.swift`, and the CoreHID publication pattern in `VirtualGamepad.swift`, were adapted from research and MIT-licensed source in:

- Project: WaveBird
- Author: Joshua Murphy
- Repository: https://github.com/murphyjt/wavebird
- Copyright: Copyright (c) 2026 Joshua Murphy
- License: MIT

WaveBird's current macOS implementation documents a real Xbox Series Bluetooth report descriptor, a 17-byte Apple-facing report, an SDL GIP companion stream, Switch Pro presentation behavior, and CoreHID virtual-device publication. WiiMacMote's code is reduced and adapted to its own canonical state, lifecycle, deployment target, and tests.

WiiMacMote does not use, copy, or depend on WaveBird's Apple signing identity, provisioning profile, or entitlement approval. The Local AMFI Lab build is independently ad-hoc signed by the developer who builds it.

### MIT License

Copyright (c) 2026 Joshua Murphy

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Protocol and architecture references

The project also uses public documentation and independent behavior references from Dolphin, xwiimote, WiiBrew, hidapi, SDL, Nintendo controller reverse-engineering projects, and Apple documentation. These references are listed in `MODERNIZATION.md`; no dependency on their binaries is introduced by WiiMacMote.

Wii Remote memory/register, IR, speaker, extension, MotionPlus, and Balance Board packet layouts were implemented from public protocol descriptions in xwiimote's `doc/PROTOCOL` and WiiBrew's Wiimote/extension technical pages. WiiMacMote contains its own Swift parsers/builders rather than copied source from those projects.
