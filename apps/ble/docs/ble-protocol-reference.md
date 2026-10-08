# BLE Protocol Reference

Technical reference for the Bluetooth Low Energy protocol handling in this app.
Everything here was derived by reading the community reference implementations
listed below — not from forum posts, marketing copy, or a plausible-looking
pattern — and, for JK-BMS, cross-checked against a real captured example frame.

**Sources.** Primarily the `syssi/esphome-*-bms` component sources on GitHub
(Apache-2.0); for JK-BMS also cross-checked against a captured frame. An earlier
revision of this project described a fabricated JK protocol (`0x4E 0x57` framing)
that never matched real hardware, and a Daly implementation built on the wrong
product line's protocol. Both were replaced. If you extend a brand, re-derive it
from the matching `esphome-*-bms` repository rather than trusting anything older.

**Never guess a protocol.** This app reads battery-management hardware. A wrong
frame format, checksum, register address, byte offset, or scaling factor does not
produce a parse error — it produces a plausible-looking wrong number about a
battery, which someone may act on. Every new decoder needs a test that fails
without it.

## 📶 Verified BLE Protocol Specifications

> **Scope note — read before editing.** JKBMSR publicly supports **JK-BMS only**.
> The non-JK rows below are **internal protocol implementations retained for
> reuse**, not support claims, and must never appear in public copy, the Play
> listing, the welcome screen, or the compatibility page. They are kept because:
>
> - The multi-brand candidate set is what makes service-UUID collision ranking
>   reliable for JK-BMS itself (`0xFFE0` is shared by four protocols, `0xFF00`
>   by five). Trimming `_signatures` would make the scanner award a confident
>   "exclusive service" score to a non-JK device and then write JK02 frames to
>   it. `BrandRegistry.serviceSharingCount` must keep counting every signature.
> - `BmsProtocolHelper.detectBrandFromName` must keep recognising a non-JK
>   device as *itself*; mislabelling it JK-BMS is worse than showing
>   "unsupported".
> - `BmsCapabilities.forBrand` is per-vendor truth that gates real MOSFET
>   writes. Never merge capability logic with the `BmsBrand.isPublic`
>   presentation flag.
>
> Presentation is gated on `BmsBrand.isPublic` / `BrandRegistry.selectableBrands`.
> Detection, the capability matrix, and the API's accepted `bmsVendor` value set
> are deliberately untouched.

Every protocol below was rewritten this project by reading the actual `syssi/esphome-*-bms` component source (not summaries, not forum posts) and, for JK-BMS, cross-checked against a real captured example frame. An earlier version of this file described a fabricated JK protocol (`0x4E 0x57` framing) that never matched real hardware and a Daly implementation based on the wrong product line's protocol — both have been replaced. Treat this table as the current source of truth; if you're extending a brand, re-derive from the matching `esphome-*-bms` repo rather than reusing anything older than this rewrite.

| Brand | GATT Service / Char | Frame header | Checksum | Notes |
|---|---|---|---|---|
| **JK-BMS (JK02)** | Service `0xFFE0`, char `0xFFE1` (write + notify) | Cmd: `AA 55 90 EB`; Resp: `55 AA EB 90`, fixed 300 bytes | Sum of preceding bytes & 0xFF | Notifications arrive as ~20-byte fragments — **must** be reassembled before parsing (`isCompleteJk02Frame`). Assumes JK02_24S frame layout (24 cell slots); JK02_32S shifts fields +32 bytes and isn't distinguished yet. |
| **Daly Smart BMS (D2)** | Service `0xFFF0`, notify `0xFFF1`, control `0xFFF2` | `D2 [func] [addrHi addrLo] [valHi valLo] [crc]` | Modbus CRC16 (init 0xFFFF, poly 0xA001) | Real protocol is Modbus-style register read/write — not the checksum-sum UART format used in earlier revisions of this app (different Daly product line). |
| **JBD / Xiaoxiang / Overkill Solar** | Service `0xFF00`, notify `0xFF01`, control `0xFF02` | `DD [func] 00 [len] [payload] [crc] 77` | Two's complement of sum(status+len+payload) | Telemetry split across two responses (BasicInfo `0x03` then CellInfo `0x04`) — merged via `BmsProtocolHelper.withCells`. |
| **ANT BMS** | Service `0xFFE0`, char `0xFFE1` | `7E A1 [func] [addrLo addrHi] [value] [crc] AA 55` | Modbus CRC16 | Switches use two distinct addresses (turn-on / turn-off) per switch, not a value written to one address. |
| **Seplos Active Balancer** | Service `0xFF00`, notify `0xFF01`, control `0xFF02` | `7E 10 00 46 [func] [lenHi lenLo] [payload] [crc] 0D` | XMODEM CRC16 (init 0x0000, poly 0x1021) | Single "single machine data" frame (`0x61`) carries all core telemetry; switch writes use function `0xAA` with a register/bit + on/off byte. |
| **Tianpower** | Service `0xFF00`, notify `0xFF01`, control `0xFF02` | `55 04 [type] AA`; Resp: `55 14 [type] ... AA`, fixed 20 bytes | None (start/end markers only) | Monitoring only (no switch component upstream). Only the Status frame (`0x83`) is requested — cell voltages (split across two chunk frames) aren't merged in this app yet. |
| **Basen** | Service `0xFA00`, notify `0xFA01`, control `0xFA02` | `[0x3A/0x3B] [addr] [func] [len] [payload] [crc lo hi] 0D 0A` | Plain 16-bit sum | Charge/discharge are two bits of one holding register (`0x011D`) — writes must preserve the other bit, reconstructed from the last-known status the same way upstream does. Cell-voltage chunk frames aren't merged in this app yet. |
| **KS48100** | Service `0xFF00`, notify `0xFF01`, control `0xFF02` | `7B [type] [len] [payload] 7D` | None (exact length only) | Each BLE notification is treated as one complete frame — upstream doesn't reassemble fragments for this brand either. Cell voltages are a second frame, requested reactively after Status. |
| **Offgridtec (OGT)** | Service `0xFFF0`, notify `0xFFF4`, control `0xFFF6` | ASCII text, single-byte XOR "encryption" | N/A | **Detected but not implemented.** Requires a per-device encryption key and device sub-type (A/B) with no sane default upstream — this app has no way to obtain those automatically, so guessing would risk showing fabricated data. `BmsCapabilities.forBrand(ogt)` is empty on purpose. |
| **Topband (v1)** | Service `0xFFE0`, notify `0xFFE4` | 1 raw SOF byte (`0x5E`/`0x83`/`0xB0`) + 112 ASCII-hex chars = 113 bytes | Big-endian 16-bit sum over the decoded first 54 bytes | Passive/receive-only — streams automatically once notifications are enabled, no request needed. Monitoring only. |
| **Lolan** | Service `0xFFE0`, notify `0xFFE1`, control `0xFFE2` | Req: `[funcHi funcLo] [password, 4 bytes BE]` (6 bytes) | None on Status/CellInfo (only the separate Settings frame is checksummed, and isn't requested here) | Values are IEEE-754 float32, big-endian. Switches reuse the same request mechanism with distinct turn-on/turn-off function codes, like ANT. |

**Service UUID collisions are real and expected**: 0xFFE0 is shared by JK, ANT, Topband, and Lolan; 0xFF00 is shared by JK02 (legacy alias), JBD, Seplos, Tianpower, and KS48100. Brand is primarily resolved from the advertised/platform device name (`BmsProtocolHelper.detectBrandFromName`); an unrecognized name is ranked through `DetectionEngine.candidatesFor` (name-match 1.0 / exclusive-service 0.6 / shared-service 0.4) and — when the top candidate is probeable — confirmed by sending its real request command and watching for a byte-exact telemetry frame (`BleBmsService._startProbing`). Only when nothing matches at all does the legacy unambiguous service fallback take over (`0xFFF0` → Daly), see `BleBmsService._detectBrandFromServices`.

**Switch/control support** (`BmsCapabilities.forBrand` in `lib/models/bms_models.dart`) is scoped to what's actually verified per brand — JK-BMS has the full switch set (including JK02_32S-only extended registers); Daly, ANT, Basen, KS48100, and Lolan support charge/discharge (Daly and ANT also balance); JBD and Seplos support charge/discharge only (JBD's balancer register exists upstream but is deliberately left unexposed there, matched here); Tianpower, Topband, and OGT are monitoring-only (or fully unimplemented for OGT).

**A note on missing fields**: `BmsStatus`'s constructor defaults are demo/placeholder values (e.g. `nominalCapacityAh: 280.0`, `chargeMosEnabled: true`) inherited from this app's pre-rewrite history. Every brand parser must explicitly set every field it constructs — silently omitting one (e.g. forgetting `balanceEnabled` because a frame has no balancer bit) makes it inherit that fake default and display as if it were a real reading. Several brands here explicitly zero/false fields their frame doesn't report, with a comment explaining why — follow that pattern for any new brand rather than leaving a field unset.

**A note on connected-but-no-data-yet**: `isConnected` only means the BLE link is up, not that a real frame has parsed — a device can connect and then never successfully parse a frame (wrong characteristic, brand mismatch, protocol bug). Gate any UI that displays telemetry values on `BleBmsService.hasLiveData` (true only after `_publish()` has actually run for the current connection), not on `isConnected` alone, or you'll render `BmsStatus`'s demo defaults as if they were live hardware readings — this shipped and reached a real user before being caught (v4.13.5).

**A note on features without a verified read/write protocol**: the Settings tab's BMS-parameter editor was removed in v4.14.0 because its "save" always sent the same fabricated old `0x4E 0x57`-framed command regardless of which field was edited — real hardware would just ignore it, but the UI still showed "Saved to BMS hardware." In v4.15.0 the editor was reinstated as `BmsParametersScreen` (originally drawer → "BMS parameters"; since the Controls-tab restructure it lives in the Controls tab), built on protocol that has since been byte-verified against the `syssi/esphome-*-bms` component sources: real JK02 Settings-frame (type `0x01`) decoding for reads, plus the upstream write-register/factor tables (`number/__init__.py`) for writes — for JK02, Daly, and KS48100 only; other brands correctly show an unsupported state. Values shown come from decoded frames (`BleBmsService.settingsStream`), never placeholders, and every write is PIN-gated. The Control tab's extended JK switches (emergency/temp-sensor-bypass/display/smart-sleep/timed-data/float-mode/dry-arm/OCP2/OCP3) plus RTC time calibration remain removed — they'd need `BmsStatus` fields fed by the JK02 settings frame (which still isn't merged into the live status), and no type `0x01`-driven switch path exists. Any future write-path change still must cite and match a real reference implementation.

**Device info (JK02 frame type `0x03`) and logbook (frame type `0x05`)** are both decoded from the same 300-byte reassembled frame as telemetry. The device-info frame is verified against syssi's `decode_device_info_` (jk_bms_ble.cpp:1583) at offsets 6 (model, 16 B), 22 (hardware version, 8 B), 30 (software version, 8 B), 38 (uptime u32), 42 (power-on count u32), 78 (manufacturing date, 6 B `YYMMDD`, prefixed `20`), 86 (serial number, 11 B). The offsets are independently confirmed by the OEM JK-BMS Android app's device-info screen, which reads the same positions. The frame also carries device/setup passcodes and user data at 46/62/97/102/118 — those are credentials and are deliberately **not** decoded or surfaced. The logbook is genuine BMS-side history, not app-side accumulation: it is requested on demand with command `0xA1` (syssi's `retrieve_logbook` button, `button/__init__.py:28`; independently confirmed by the OEM app's System Log screen, which sends register `161`/`0xA1`) and answered with frame type `0x05`, whose log count is a u32 LE at offset 6 and whose entries follow from offset 11, five bytes each (u32 LE seconds + one event-code byte), capped at 50. Event-code names come from syssi's `LOGBOOK_CODES` table. The BMS sends no absolute wall-clock time for an entry, so it is presented as a relative elapsed offset, exactly as syssi formats it.

