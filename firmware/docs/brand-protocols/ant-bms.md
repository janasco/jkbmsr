# ANT-BMS Protocol Specification

Research report for the `syssi/esphome-ant-bms` repository (working copy at
`/tmp/opencode/syssi/esphome-ant-bms`, HEAD `87d89bd`). All paths below are relative to
that root. Every CRC16 / checksum value was independently recomputed and cross-checked
against the source, the test fixtures under `tests/`, and the real btsnoop HCI captures
under `docs/pdus/`. No repository source code was modified.

The repo implements four protocol variants against the same ANT BMS hardware:

| Component                    | Transport | Firmware era        | Status frame            |
| ---------------------------- | --------- | ------------------- | ----------------------- |
| `components/ant_bms`         | UART      | 2021+ (`0x7E 0xA1`) | variable (152 B @ 16S)  |
| `components/ant_bms_ble`     | BLE GATT  | 2021+ (`0x7E 0xA1`) | same as above           |
| `components/ant_bms_old`     | UART      | legacy (`0xAA 55 0xAA`) | fixed 140 bytes       |
| `components/ant_bms_old_ble` | BLE GATT  | legacy (`0xAA 55 0xAA`) | fixed 140 bytes       |

---

## 1. Overview, polling, and online status

* The 2021 components are polling components with default intervals of `5s` (UART)
  (`components/ant_bms/__init__.py:38`) and `2s` (BLE); `update()` issues one status read
  per cycle.
* Online-status tracking is a counter: every `update()` increments `no_response_count_`;
  any received frame resets it to `0` and republishes the `online_status` binary sensor
  (`components/ant_bms/ant_bms.cpp:554-567`, BLE `components/ant_bms_ble/ant_bms_ble.cpp:666`).
  UART fails the device after `MAX_NO_RESPONSE_COUNT = 5` (`ant_bms.cpp:45`); BLE after
  `MAX_NO_RESPONSE_COUNT = 10` (`ant_bms_ble.cpp:51`). On failure the charge/discharge/
  balancer text sensors and total-runtime-formatted sensor publish `"Offline"`
  (`ant_bms.cpp:569-574`).
* BLE status publishes can be throttled (`throttle`, default `0s`
  `components/ant_bms_ble/__init__.py:44`); throttled frames are dropped
  (`ant_bms_ble.cpp:398-401`). BLE sends the status request only after
  `node_state == ESTABLISHED` (`ant_bms_ble.cpp:360`).
* UART link: `baud_rate 19200`, `rx_buffer_size 384`, `rx_timeout` default `50ms`
  (`components/ant_bms/__init__.py:30-31`); `loop()` flushes the frame buffer when
  `millis() - last_byte_ > rx_timeout_` (`ant_bms.cpp:195-211`).
  Wiring (README.md:34-60): ESP32 TX=GPIO16 / RX=GPIO17, ESP8266 TX=GPIO5 / RX=GPIO4,
  plus GND and 3.3 V — the BMS does not answer unless VCC is connected (JST 1.25 mm, 4 pin).
* 2021 UART rejects the old `supports_new_commands` option and directs users to
  `ant_bms_old` (`components/ant_bms/__init__.py:32-35`).
* Reference hardware tested via faker frames and captures (README.md:13-27):
  `16ZMUB00-220501A`, `24BHUB00-211026A`, `04DMUB00-240122B`, `22AAUB00-241008A` and
  legacy 2019/2020 16S-32S packs (16ZM-TB-7-16S-300A, 24AHA-TB-24S-200A, etc.).

## 2. 2021 protocol — frame format and CRC-16

Requests and responses share one envelope; multi-byte integers are **little-endian**:

```
 0      1      2      3     4     5      6...N        crcLo  crcHi  AA 55
0x7E   0xA1  function addrLo addrHi len  payload[len]
```

* `frame_len = 6 + data[5] + 4`; the parser matches `0x7E 0xA1`, then derives the full
  length from the `len` byte (`components/ant_bms/ant_bms.cpp:242`).
* The checksum is CRC-16/Modbus (init `0xFFFF`, poly `0xA001`, bit-reflected), computed
  over the bytes starting at index 1 (`0xA1` through the last payload byte), i.e.
  `crc16(raw + 1, frame_len - 5)`, and stored little-endian at `frame_len-4` / `frame_len-3`
  (`ant_bms.cpp:249-254`, `ant_bms_ble.cpp:342-347`; polynomial at
  `components/ant_bms/ant_bms.h:214-227`).

Verified vectors (all recomputed, all match their stored bytes):

| Frame | Bytes covered | CRC  | Stored | Source |
| ----- | ------------- | ---- | ------ | ------ |
| status request `01 00 00 BE` | `A1 01 00 00 BE` | `0x5518` | `18 55` | btsnoop L4, `ant_bms.cpp:365` |
| device-info request `02 6C 02 20` | `A1 02 6C 02 20` | `0xC458` | `58 C4` | btsnoop L1 |
| settings read addr `0x0000` len 2 | `A1 02 00 00 02` | `0xA019` | `19 A0` | `frames_settings.h:22` |
| settings bulk read addr `0x0000` len `0x38` | `A1 02 00 00 38` | `0xB399` | `99 B3` | btsnoop L7 |
| auth request fn `0x23` | `A1 23 6A 01 0C 31...63` | `0x6220` | `20 62` | `ant_bms.cpp:745` |
| write `51 08` (current zero) | `A1 51 08 00 00` | `0xE708` | `08 E7` | `ant_bms_ble_test.cpp:331` |
| write `51 09` (restart) | `A1 51 09 00 00` | `0x2759` | `59 27` | `ant_bms_ble_test.cpp:337` |
| write `51 0B` (shutdown) | `A1 51 0B 00 00` | `0xE7F8` | `F8 E7` | `ant_bms_ble_test.cpp:343` |
| write `51 0C` (factory reset) | `A1 51 0C 00 00` | `0x2649` | `49 26` | `ant_bms_ble_test.cpp:373` |
| write `51 0F` (clear system log) | `A1 51 0F 00 00` | `0x26B9` | `B9 26` | btsnoop L25 |
| settings response `12 00 00 02 36 10` | `A1 12 00 00 02 36 10` | `0x141F` | `1F 14` | `frames_settings.h:84` |
| 16S status response | bytes 1..147 | `0x4305` | `05 43` | `frames_16s_status.h:19` |
| write ACK reg `0x04` | `A1 61 04 00 02 01 00` | `0x2BF2` | `F2 2B` | `ant_bms.cpp:216` |
| write ACK reg `0x06` | `A1 61 06 00 02 01 00` | `0xEB8B` | `8B EB` | `ant_bms.cpp:217` |
| write ACK reg `0x07` (app) | `A1 61 07 00 02 01 00` | `0x2BB6` | `B6 2B` | btsnoop L13/19 |
| write ACK reg `0x0F` (app) | `A1 61 0F 00 02 03 00` | `0x8A56` | `56 8A` | btsnoop L25 |
| permission req fn `0x22` | `A1 22 00 00 02 42 0E` | `0xECBD` | `BD EC` | btsnoop L10 |
| permission resp fn `0x42` | `A1 42 00 00 02 42 0E` | `0x4CB4` | `B4 4C` | btsnoop L11 |
| permission req fn `0x22` addr `0x0202` | `A1 22 02 00 02 DE 0D` | `0x2DED` | `ED 2D` | btsnoop L16 |
| permission resp fn `0x42` addr `0x0202` | `A1 42 02 00 02 DE 0D` | `0x8DE4` | `E4 8D` | btsnoop L17 |

The response function is the request function plus `0x10`
(`0x01 -> 0x11`, `0x02 -> 0x12`, `0x23 -> 0x43`, `0x51 -> 0x61`, `0x22 -> 0x42`),
confirmed in the password-ACK comment `7E A1 43 6A 01 02 05 00 1E 5C AA 55`
(`components/ant_bms/ant_bms.cpp:215`).

## 3. 2021 commands

### 3.1 Status read — function `0x01` (response `0x11`)
`7E A1 01 00 00 BE crc aa 55`. `0xBE` (190) is the payload length of the largest status
frame (32 cells). Used every poll on both transports
(`ant_bms.cpp:727-743` `read_registers_`, `ant_bms_ble.cpp:358-367`).

### 3.2 Device info / settings read — function `0x02` (response `0x12`)
The command is addressable. Responses are routed on the little-endian address
`data[3..4]` (`ant_bms.cpp:285-291`, `ant_bms_ble.cpp:383-389`):
* `0x026C`, len `0x20` -> device info, requested once per BLE connection immediately
  after `ESP_GATTC_REG_FOR_NOTIFY_EVT` (`ant_bms_ble.cpp:271-279`);
* any other address -> settings register read (`on_settings_data_`,
  `ant_bms.cpp:496`, `ant_bms_ble.cpp:645`).

`read_settings(address)` uses a 2-byte data length, except for the three uint32
addresses `0x00A2` / `0x00A6` / `0x00AA` which use 4 bytes
(UART `ant_bms.cpp:540-552`, BLE `ant_bms_ble.cpp:852-862`).

### 3.3 Register write — function `0x51` (ack `0x61`)
BLE: `send_(0x51, address, value, true)` sends the auth frame, then
`7E A1 51 addrLo addrHi valueByte crc aa 55` via `build_frame`
(`ant_bms_ble.cpp:831-845, 848-849, 929-945`).
UART: `write_register(uint8_t address, uint16_t value)` sends
`7E A1 51 addr8 valueHi valueLo crc aa 55` (`ant_bms.cpp:522, 794-808`) — note the
**8-bit address / 16-bit value** layout, the inverse of BLE.
The device replies with an ACK `0x61` echoing address, length and value, e.g.
`7E A1 61 04 00 02 01 00 F2 2B AA 55`. The UART `send_` also authenticates before every
command (`ant_bms.cpp:810-815`).

Known command registers used by the BLE buttons and switches
(`components/ant_bms_ble/button/__init__.py`, `components/ant_bms_ble/switch/__init__.py`):

| Register(s) | Action |
| ----------- | ------ |
| `0x0001` / `0x0003` | discharging OFF / ON |
| `0x0004` / `0x0006` | charging ON / OFF |
| `0x0008` | current zero |
| `0x0009` | restart |
| `0x000B` | shutdown |
| `0x000C` | factory reset |
| `0x000D` / `0x000E` | balancer ON / OFF |
| `0x000F` | clear system log |
| `0x0010` | Bluetooth initialization |
| `0x001C` / `0x001D` | Bluetooth OFF / ON |
| `0x0020` / `0x0021` | clear discharge / charge cycle Ah |
| `0x0022` / `0x0023` | clear discharge / charge time |
| `0x0024` / `0x0025` | clear running time / protection time |
| `0x002A` | reset hardware |
| `0x002C` | save customer data |

All write-ACK frames above were byte-verified against `ant_bms_ble_test.cpp` (frame
builder tests, lines 331-425) and `docs/pdus/btsnoop_hci_ANT-BLE16ZMUB-reduced.txt`.

### 3.4 Authentication — function `0x23` (response `0x43`)
`authenticate_()` sends
`7E A1 23 6A 01 0C 31 32 33 34 35 36 37 38 39 61 62 63 crc aa 55`: address `0x016A`,
length 12, payload is the fixed ASCII literal `"123456789abc"`
(`ant_bms.cpp:745-776`, `ant_bms_ble.cpp:864-903`). The 2021 components expose **no
configurable password**; this fixed value is always used. `authenticate_variable_()`
sends arbitrary payloads (`ant_bms.cpp:778`, `ant_bms_ble.cpp:905`). The controller
replies with `7E A1 43 6A 01 02 <2 bytes> crc aa 55`.

### 3.5 Observed but unhandled commands
* `0x22` / `0x42` permission handshake — appears in the mobile-app capture before
  register writes; the components log it as an unhandled response
  (`ant_bms.cpp:293-296`).
* `0x04` / `0x14` — OTA-style config read (len `0x0C`, response carries a 19-byte block).
  Present in the app capture only.

## 4. Response routing and device-info payload

Dispatch (`ant_bms.cpp:275-297`, `ant_bms_ble.cpp:373-395`):
* `0x11` -> status decode;
* `0x12` -> device info if address == `0x026C`, otherwise settings;
* anything else -> warning.

Device info payload (`7E A1 12 6C 02 20 ... AA 55`, 48 bytes):

| Offset | Len | Field |
| ------ | --- | ----- |
| `6..21` | 16 | ASCII hardware model, NUL-terminated -> `device_model` text sensor |
| `22..37` | 16 | ASCII software version, NUL-terminated -> `software_version` |
| `38..39` | 2 | CRC16 over bytes 1..42 (LE) |
| `40..43` | 4 | reserved (`FF 0B 00 00`) |
| `44..45` | 2 | `0x41F2` — stale/unused CRC bytes |
| `46..47` | 2 | `AA 55` end marker |

Decoded at `ant_bms.cpp:477-494` / `ant_bms_ble.cpp:604-643`. The device-info frame
violates the generic `6 + len + 4` rule (its `len = 0x20` is larger than the logical
payload); the BLE parser special-cases function `0x12` for the length check
(`ant_bms_ble.cpp:328-333`). Real example: model `16ZM`, version `16ZMUB00-211026A`;
a 2026 pack returns model `22PHB8TB130A`, version `22AAUB00-241008A`
(`frames_16s_status.h:34-49`).# ANT-BMS Protocol Specification — part 2 (status decode, BLE, UART)

## 5. Status frame decode (2021, function `0x11`)

All multi-byte fields are **little-endian** (`ant_get_16bit` / `ant_get_32bit`,
`ant_bms.cpp:300-305`). The frame is variable-length; fields following the cell-voltage
block are located with:

```
offset = 2 * cell_count + 2 * temperature_sensor_count
```

The canonical absolute offsets below are for a 16S / 2-NTC frame (offset 36,
frame length 152, as in `tests/components/ant_bms_ble/frames_16s_status.h`):

| Abs | Len | Field | Type and scale |
| --- | --- | ----- | -------------- |
| `6` | 1 | Permissions flags | byte (logged only) |
| `7` | 1 | Battery status | byte -> `BATTERY_STATUS` map |
| `8` | 1 | Number of temperature sensors | byte, max 4 |
| `9` | 1 | Number of cells | byte, max 32 -> `battery_strings` |
| `10` | 8 | Protection bitmask | bytes (not published) |
| `18` | 8 | Warning bitmask | bytes (not published) |
| `26` | 8 | Balancing/other bitmask | bytes (not published) |
| `34 + i*2` | 2 | Cell voltage i (1..cells) | uint16 x 0.001 V |
| `70` | 2 | NTC temperatures 1..n | int16 x 1 C |
| `74` | 2 | MOSFET temperature | int16 x 1 C |
| `76` | 2 | Balancer temperature | int16 x 1 C |
| `78` | 2 | Total voltage | uint16 x 0.01 V |
| `80` | 2 | Current | int16 x 0.1 A |
| `82` | 2 | State of charge | uint16 x 1 % |
| `84` | 2 | State of health | uint16 x 1 % |
| `86` | 1 | Charge MOSFET status | byte -> `CHARGE_MOSFET_STATUS` |
| `87` | 1 | Discharge MOSFET status | byte -> `DISCHARGE_MOSFET_STATUS` |
| `88` | 1 | Balancer status | byte -> `BALANCER_STATUS` |
| `94` | 4 | Total battery capacity setting | uint32 x 1e-6 Ah |
| `98` | 4 | Capacity remaining | uint32 x 1e-6 Ah |
| `102` | 4 | Battery cycle capacity | uint32 x 0.001 Ah |
| `106` | 4 | Power | int32 x 1 W |
| `110` | 4 | Runtime | uint32 s |
| `114` | 4 | Balanced-cell bitmask | uint32 (bit i = cell i) |
| `118` | 2 | Maximum cell voltage | uint16 x 0.001 V |
| `120` | 2 | Cell number of max | uint16 |
| `122` | 2 | Minimum cell voltage | uint16 x 0.001 V |
| `124` | 2 | Cell number of min | uint16 |
| `126` | 2 | Delta cell voltage | uint16 x 0.001 V |
| `128` | 2 | Average cell voltage | uint16 x 0.001 V |
| `130` | 2 | Discharge-MOSFET D-S voltage | uint16 x 0.01 V |
| `132` | 2 | Drive voltage discharge MOSFET | uint16 x 0.1 V |
| `134` | 2 | Drive voltage charge MOSFET | uint16 x 0.1 V |
| `136` | 2 | F40com | uint16 |
| `138` | 2 | Battery type | `0xFAF1` ternary, `0xFAF2` LFP, `0xFAF3` LTO, `0xFAF4` custom |
| `140` | 4 | Total discharging capacity | uint32 x 0.001 Ah |
| `144` | 4 | Total charging capacity | uint32 x 0.001 Ah |
| `148` | 4 | Total discharging time | uint32 s |
| `152` | 4 | Total charging time | uint32 s |
| `156` | 2 | CRC16 (bytes 1..155) | LE |
| `158` | 2 | `AA 55` | end-of-frame |

(Offset arithmetic and reads: `ant_bms.cpp:326-474`; identical routine with the annotated
byte table in `ant_bms_ble.cpp:397-601`.)

Status-code string tables:
* `CHARGE_MOSFET_STATUS`, 21 entries (`ant_bms.cpp:57-79`): Off, On, Overcharge
  protection, Over current protection, Battery full, Total overpressure, Battery over
  temperature, MOSFET over temperature, Abnormal current, Balanced line dropped string,
  Motherboard over temperature, Reserved, Open failed, Discharge MOSFET abnormality,
  Waiting, Manually turned off, Two level exceed voltage, Low temperature protection,
  Voltage difference exceeded, Reserved, Self detect error.
* `DISCHARGE_MOSFET_STATUS`, 20 entries (`ant_bms.cpp:82-103`): Off, On, Overdischarge
  protection, Over current protection, Two current exceeded, Total pressure
  undervoltage, Battery over temperature, MOSFET over temperature, Abnormal current,
  Balanced line dropped string, Motherboard over temperature, Charge MOSFET on, Short
  circuit protection, Discharge MOSFET abnormality, Open failed, Manually turned off,
  Two level low voltage, Low temperature protection, Voltage difference exceeded, Self
  detect error.
* `BATTERY_STATUS`, 6 entries (`ant_bms.cpp:106-113`): 0 Unknown, 1 Idle, 2 Charge,
  3 Discharge, 4 Standby, 5 Error.
* `BALANCER_STATUS`, 11 entries (`ant_bms.cpp:116-128`): Off, Exceeds the limit
  equilibrium, Charge differential pressure balance, Balanced over temperature,
  Automatic equalization, + Unknown x5, Motherboard over temperature.

The charge/discharge/balancer `switch` entities mirror the raw codes: charging switch =
(charge status == 1), discharging switch = (discharge status == 1), balancer switch =
(balancer status == 4 "Automatic equalization") (`ant_bms_ble.cpp:514,525,530`).

Verified decode (faker frame, `frames_16s_status.h:19-28` and assertions in
`ant_bms_ble_test.cpp`): 16 cells (3.300..3.305 V), battery_strings 16, 2 NTCs,
total 52.84 V, current 0.3 A, SOC 91, SOH 100, capacities 280.0 / 252.602 / 4862.65 Ah,
power 15 W, runtime 36 591 632 s -> "1y 58d 12h", temps 1/2 C, mosfet 2 C, balancer 7 C,
charge/discharge On, balancer Off, max 3.305 V (cell 16), min 3.300 V (cell 1),
delta 0.005 V, avg 3.302 V, discharging/charging capacity 3902.649 / 5822.651 Ah,
times 4 402 650 / 4 830 952 s.

## 6. BLE transport (2021)

* GATT service `0xFFE0`; write/notify characteristic `0xFFE1` at handle `0x10`,
  properties `0x1c`; a second characteristic `0xFFE2` at handle `0x13`, properties
  `0x0c` (`components/ant_bms_ble/ant_bms_ble.cpp:53-54`; observed service range
  `start_handle 0xe end_handle 0xffff`, `ant_bms_ble.cpp:249-253`).
* All writes go out via `esp_ble_gattc_write_char` with `ESP_GATT_WRITE_TYPE_NO_RSP`
  (`ant_bms_ble.cpp:894-896`).
* Session sequence: `ESP_GATTC_SEARCH_CMPL_EVT` -> resolve `0xFFE1` and
  `esp_ble_gattc_register_for_notify` (`ant_bms_ble.cpp:241-270`);
  `ESP_GATTC_REG_FOR_NOTIFY_EVT` -> send the device-info request
  (`ant_bms_ble.cpp:271-279`); afterwards `update()` polls the status register. On
  disconnect the characteristic handle is cleared and notifications unregistered
  (`ant_bms_ble.cpp:225-240`).
* Frame reassembly (`assemble()`, `ant_bms_ble.cpp:298-355`):
  * null / zero-length notifications ignored; buffer > `MAX_RESPONSE_SIZE` dropped;
  * buffer flushed on a fresh `7E A1` preamble;
  * a frame is committed only when the buffer ends with the full `AA 55` pair — a lone
    trailing `0x55` (such as the ASCII `'U'` inside a version string) is not accepted
    (issue #172); guarded in `ant_bms_ble_test.cpp:280-292`;
  * the length byte is validated against the buffer before CRC parse to avoid
    out-of-bounds reads on an inflated `data_len` (issue #174,
    `ant_bms_ble_test.cpp:311-319`);
  * CRC mismatch discards the buffer (`ant_bms_ble.cpp:342-347`).

## 7. UART transport (2021)

* Byte-at-a-time state machine `parse_ant_bms_byte_` (`ant_bms.cpp:219-267`) with a
  50 ms idle timeout flush in `loop()` (`ant_bms.cpp:195-211`).
* Polling: `update()` -> `read_registers_()` sends `7E A1 01 00 00 BE 18 55 AA 55`
  (`ant_bms.cpp:727`). UART never requests device info and never populates the
  `device_model` / `software_version` text sensors.
* `read_settings` uses `build_settings_frame` (address LE + len `0x02`/`0x04`,
  `ant_bms.cpp:524-538`).
* `build_frame` for writes: `7E A1 51 addr8 valueHi valueLo crc aa 55`
  (`ant_bms.cpp:794-808`) — 8-bit address / 16-bit value, opposite of the BLE frame
  builder (`ant_bms_ble.cpp:831-845`: 16-bit address / 8-bit value). A pure 16-bit
  address byte is fine for every register the component uses (all command registers are
  single-byte, settings reads go through `build_settings_frame`).
* Example configs: `esp32-example.yaml` / `esp8266-example.yaml` — `baud_rate 19200`,
  `rx_buffer_size 384`, `rx_timeout 50ms`.# ANT-BMS Protocol Specification — part 3 (legacy, settings, verification, inventory)

## 8. Legacy protocol (`AA 55 AA`, fixed 140-byte status frames)

### 8.1 Frame and checksum
Legacy responses carry the header `AA 55 AA FF` (three start bytes plus the fixed
function byte `0xFF` for status) and are exactly 140 bytes; multi-byte fields are
**big-endian** (`components/ant_bms_old/ant_bms_old.cpp:100-146`,
`components/ant_bms_old_ble/ant_bms_old_ble.cpp`).

The integrity check is a plain 8-bit additive sum of the payload, stored big-endian:

```
checksum = sum(data[4..137]);   stored = data[138] << 8 | data[139]
```

(chksum implemented at `ant_bms_old.h:162-166`, checked at `ant_bms_old.cpp:131-136`.)
Verified on the faker fixtures: 8S frame sum `0x0EDF` = stored `0E DF`
(`tests/components/ant_bms_old/frames_8s.h`); 14S frame sum `0x15F4` = stored `15 F4`
(`tests/components/ant_bms_old_ble/frames_14s.h`). (Legacy registers are single-byte,
so the sum never overflows the 8-bit accumulator before the high byte.)

### 8.2 Requests (all 6 bytes)
| Purpose | Frame | Checksum byte |
| ------- | ----- | ------------- |
| Read all (BLE) | `DB DB 00 00 00 00` | — |
| Read all (UART) | `5A 5A 00 00 01 01` | `0x01` (`addr+hi+lo`) |
| Read all (RFCOMM/PC app) | `5A 5A FF 00 00 FF` | `0xFF` |
| Write register | `A5 A5 addr hi lo sum` | `(addr+hi+lo) & 0xFF` |
| Write apply | `A5 A5 FF 00 00 FF` | `0xFF` |

`send_` is at `ant_bms_old.cpp:458-469` / `ant_bms_old_ble.cpp:506-525`;
`read_registers_` sends `5A 5A 00 00 01 01` on UART (`ant_bms_old.cpp:471`) and
`DB DB 00 00 00 00` on BLE (`ant_bms_old_ble.cpp:527`). The `5A 5A FF 00 00 FF`
RFCOMM variant appears in the model2019 PC-app capture (`docs/pdus/`).

### 8.3 Writes and password authentication
`write_register(address, value)` sends the value frame, then the apply frame
`A5 A5 FF 00 00 FF` (`ant_bms_old.cpp:439-443`, `ant_bms_old_ble.cpp:487-491`).
When a password is set, every write is prefixed by 4 authentication frames
`A5 A5 (0xF1+i) hi lo sum` (i = 0..3) carrying the 8 password characters, two bytes per
frame — `(password[2i] << 8) | password[2i+1]` (`ant_bms_old.cpp:445-456`,
`ant_bms_old_ble.cpp:493-504`). Password config accepts exactly 8 characters or an empty
string (`ant_bms_old/__init__.py:33-36`, `ant_bms_old_ble/__init__.py:33-36`).

### 8.4 Status decode offsets (legacy)
`on_status_data_` at `ant_bms_old.cpp:165+` (mirrored in `ant_bms_old_ble.cpp:220+`).
The cell count is `data[123]`; the six temperature slots are always decoded.

| Off | Len | Field | Scale |
| --- | --- | ----- | ----- |
| `4` | 2 | Total voltage | x 0.1 V |
| `6 + i*2` (i = 0..31) | 2 | Cell voltage i (count = `data[123]`) | x 0.001 V |
| `70` | 4 | Current | int32 x 0.1 A |
| `74` | 1 | SOC | % |
| `75` | 4 | Total battery capacity setting | uint32 x 1e-6 Ah |
| `79` | 4 | Capacity remaining | uint32 x 1e-6 Ah |
| `83` | 4 | Cycle capacity | uint32 x 0.001 Ah |
| `87` | 4 | Uptime | uint32 s |
| `91 + i*2` (i = 0..5) | 2 | Temperature | int16 x 1 C |
| `103` | 1 | Charge MOSFET status | byte |
| `104` | 1 | Discharge MOSFET status | byte |
| `105` | 1 | Balancer status | byte |
| `106` | 2 | Tire length | mm |
| `108` | 2 | Pulses per week | |
| `110` | 1 | Relay switch | byte |
| `111` | 4 | Power | int32 W |
| `115` | 1 | Max-voltage cell number | |
| `116` | 2 | Max cell voltage | x 0.001 V |
| `118` | 1 | Min-voltage cell number | |
| `119` | 2 | Min cell voltage | x 0.001 V |
| `121` | 2 | Average cell voltage | x 0.001 V |
| `123` | 1 | Cell count / battery strings | |
| `124` | 2 | Discharge MOSFET D-S voltage | x 0.01 V |
| `126` | 2 | Drive voltage (discharge) | x 0.1 V |
| `128` | 2 | Drive voltage (charge) | x 0.1 V |
| `130` | 2 | Comparator initial value (current = 0) | |
| `132` | 4 | Balancing cell bitmask | |
| `136` | 2 | System log / overall status bitmask | |
| `138` | 2 | Checksum | BE |

Same table is in `README.md:148-219`. Decoded 14S example (frames_14s.h:8-18):
48.8 V, cells 3.468..3.509 V, 8.0 A, SOC 41, 170.0 Ah configured / 68.770 Ah remaining /
11109.391 Ah cycled, runtime 16 386 097 s, temps 22/21/21/21/21/21 C, charge+discharge
On, balancer Off, max cell 9 (3.509 V), min cell 14 (3.468 V), delta 0.041 V,
avg 3.487 V, power 390 W.

### 8.5 Legacy registers (buttons/switches)
`components/ant_bms_old{,_ble}/button/__init__.py` and `switch/__init__.py` bind
`AntButton::press_action` / `AntSwitch::write_state` to `parent_->write_register`
(`ant_bms_old/button/ant_button.cpp:10`, `ant_bms_old/switch/ant_switch.cpp:10`):

| Register | Action |
| -------- | ------ |
| `0xF7` | shutdown / power off |
| `0xF8` | clear counter (Ah) |
| `0xF9` | discharge MOSFET (switch) |
| `0xFA` | charge MOSFET (switch) |
| `0xFC` | balancer |
| `0xFD` | factory reset |
| `0xFE` | restart / Bluetooth stop |
| `0xFF` | apply/save write (sent after every write) |
| `0xF1..0xF4` | password auth (4 x pairs) |

## 9. Settings registers and select entities

The select entities read the protected parameters through function `0x02`
(`components/ant_bms/select/__init__.py`; entity control -> `parent_->read_settings`,
`components/ant_bms/select/ant_select.cpp:22`). The authoritative register map is
`SETTINGS_REGISTERS` in `components/ant_bms/ant_bms.cpp:136-193` (57 entries; the same
list drives `select/__init__.py`). Decoding in `on_settings_data_`
(`ant_bms.cpp:496-514`, `ant_bms_ble.cpp:645-664`): 16-bit value for len 2, 32-bit value
for len 4, scaled. Example: addr `0x0000`, raw `0x1036` -> 4.150 V
(`frames_settings.h:81-86`).

Address groups and scales:
* `0x0000..0x0032` (paired protect/recover, L2 variants for cells and pack): cell
  thresholds x 0.001 V; pack thresholds x 0.1 V. Pairs: 0x0000/2 cell OVP, 0x0004/6
  cell OVP L2, 0x0008/A pack OVP, 0x000C/E cell UVP, 0x0010/2 cell UVP L2, 0x0014/6
  pack UVP, 0x0018/A delta protect, 0x0020/2 cell over-V warn, 0x0024/6 pack over-V
  warn, 0x0028/A cell under-V warn, 0x002C/E pack under-V warn, 0x0030/2 delta warn.
* Current protection `0x0068..0x0076`: charge OCP x 0.1 A (+delay s, +L2 A/ms),
  discharge OCP x 0.1 A (+delay s, +L2 A/ms), short-circuit A (+delay us).
* Current warnings `0x007C..0x0082`: charge/discharge OCP warning x 0.1 A (+ recovery
  pair each).
* SOC warnings `0x0084` / `0x0086`: SOC low level 1/2, %.
* Balancing `0x008C..0x0096`: cell balancing voltage x 0.001 V, start voltage,
  difference ON/OFF x 0.001 V, balancing current mA, charging current x 0.1 A.
* Chemistry & config `0x0098..0x009E`: cell type, cell number (S), internal resistance
  calibration mOhm, shutdown voltage x 0.001 V.
* Charge request `0x00A0`: request charge current x 0.1 A.
* Capacity (uint32, 4-byte reads) `0x00A2`/`0x00A6`/`0x00AA`: nominal / remaining /
  total cycle capacity, Ah.
* `0x00C4` SOC method; `0x017A` tire length mm; `0x017C` pulse value; `0x017E`
  secondary module number.

The 57 request frames are byte-tested in `tests/components/ant_bms_ble/frames_settings.h`
(e.g. `0x0000/len2 -> 7E A1 02 00 00 02 19 A0 AA 55`, `0x00A2/len4 -> ... 38 40 ...`).

## 10. Verification corpus, fixtures, and quirks

### 10.1 Test fixtures
* `tests/components/ant_bms_ble/frames_16s_status.h` — 152-byte 16S status frame, a
  device-info frame (`16ZM`) and the issue-#172 device frame (`22PHB8TB130A`).
* `tests/components/ant_bms_ble/frames_settings.h` — 57 settings-register cases plus the
  `0x0000 -> 0x1036` response.
* `tests/components/ant_bms_old/frames_8s.h` and
  `tests/components/ant_bms_old_ble/frames_14s.h` — legacy 140-byte status frames.
* `tests/components/<component>/common.h` — `TestableAntBms*` wrappers exposing
  `assemble()`, plus `test.host.yaml` component-validation configs.
* `tests/components/<component>/<component>_test.cpp` — decode assertions and,
  for BLE, byte-exact frame-builder expectations (listed CRC vectors above) and
  parser robustness tests (zero-length, 1-byte preamble, inflated len, fragment ending
  on embedded `0x55`).

### 10.2 Offline captures (`docs/pdus/`)
* `btsnoop_hci_ANT-BLE16ZMUB-reduced.txt` — clean 2021 BLE session: device-info request,
  status request, bulk settings read (`0x02 00 00 38`), permission handshake `0x22/0x42`,
  register writes `0x51 0x07` and `0x51 0x0F` with `0x61` ACKs.
* `btsnoop_hci_ANT-BLE16ZMUB.txt` / `...-24BHUB*.log` — full sessions incl. extended
  `0x14` config reads.
* `btsnoop_hci_model2019-BMS-ANT24C-rfcomm.*` — legacy RFCOMM session with
  `5A 5A FF 00 00 FF` read frames and `A5 A5` writes.
* `model2021-req-5a5a00000101.txt`, `model2021-req-dbdb00000000.txt`,
  `model2021-req-7ea1010000be1855aa55.txt`, `model2019-req-dbdb00000000.txt` — isolated
  read-request probes proving each transport's read frame.

### 10.3 Quirks and caveats
* Device-info `data_len` is larger than the logical payload; BLE reassembly special-cases
  it (`ant_bms_ble.cpp:328-333`).
* An ASCII `U` (`0x55`) inside the software version string must not match the frame
  terminator (issue #172); end-of-frame requires the full `AA 55`.
* `0xF1 0xFA` battery-type bytes and `0x41F2` byte pair in the device-info trailer are
  descriptive only and are not decoded into sensors.
* README known issues: enabling every sensor can overflow the ESP32 stack (increase
  stack size); there is no command queue, so rapid home-assistant writes are
  unreliable.
* The device must see 3.3 V on the comm-port VCC pin or it stays silent
  (README.md:60). TX/RX swap is a common wiring error (`README.md:34-58`).

## 11. Per-file inventory

### components/ant_bms (UART, 2021 protocol)
* `__init__.py` — UART component registration; `rx_timeout` (default 50 ms); rejects old
  `supports_new_commands`; polling 5 s.
* `ant_bms.h` — class, polling/UART membership, `crc16()` inline, build/send/parse API.
* `ant_bms.cpp` — status tables, `SETTINGS_REGISTERS`, frame parser, CRC check, decode,
  device-info/settings decode, poll/online tracking, frame builders, auth.
* `sensor.py`, `ant_bms_sensor.h/.cpp` — sensor schemas and publish helpers.
* `text_sensor.py`, `ant_bms_text_sensor.h/.cpp` — text-sensor schemas (status strings)
  and helpers.
* `binary_sensor.py`, `ant_bms_binary_sensor.h/.cpp` — online binary sensor.
* `button/__init__.py`, `ant_button.h/.cpp` — command buttons (write register 0x0000).
* `switch/__init__.py`, `ant_switch.h/.cpp` — charging/discharging/balancer switches.
* `select/__init__.py`, `ant_select.h/.cpp` — 57 settings select entities; open sends a
  settings read.

### components/ant_bms_ble (BLE, 2021 protocol)
* `__init__.py` — ble_client node, `throttle` (default 0 s), polling 2 s.
* `ant_bms_ble.h` — class, `crc16()`, assembler state, GATT abstracts.
* `ant_bms_ble.cpp` — GATT discovery/notify/events, frame reassembly, decode (shared
  logic with `ant_bms`), build/read/write/auth.
* `sensor.py/text_sensor.py/binary_sensor.py/switch/__init__.py/button/__init__.py` —
  same schema surface as UART incl. device model/software version text sensors.

### components/ant_bms_old (UART, legacy 0xAA protocol)
* `__init__.py` — UART component, 8-char password or empty, polling 5 s.
* `ant_bms_old.h/.cpp` — 140-byte parser, additive checksum, decode, `send_`,
  auth, write+apply.
* `sensor.py/text_sensor.py/binary_sensor.py/button/ant_button.cpp/switch/ant_switch.cpp`
  — legacy-schema entities (single protection/mosfet tables).

### components/ant_bms_old_ble (BLE, legacy 0xAA protocol)
* `__init__.py` — ble_client node, 8-char password or empty.
* `ant_bms_old_ble.h/.cpp` — service `0xFFE0`/char `0xFFE1`, notify reassembly of
  140-byte frames, decode, `send_`, auth.
* `sensor.py/text_sensor.py/binary_sensor.py/button/ant_button.cpp/switch/ant_switch.cpp`
  — legacy entities; buttons incl. shutdown/clear-counter/factory-reset/restart.

### Examples (root of repo)
21 YAML examples: `esp32-(ble-)?(old-)?example{,-debug,-faker,{-multiple-devices}}.yaml`,
`esp32-ble-scanner.yaml`, `esp8266-(old-)?example{,-debug,-faker}.yaml`, plus `secrets.yaml`
template in README. Faker examples feed the deterministic frames used by the tests.

### tests/
* `components/<component>/{common.h,*_test.cpp,frames_*.h,test.host.yaml}` — unit-test
  harnesses, fixture frames, decode assertions, byte-exact frame builders.
* `esp*.yaml` and `test_component_schemas.py` — integration/CI config validation.
* `run-cpp-tests.sh`, `test-esp32.sh`, `test-esp8266.sh` — CI runners.

### docs/
* `ANT_communication_protocol_EN.1.pdf` — vendor protocol document (reference).
* `pdus/*.txt|*.log` — btsnoop/RFCOMM captures (test corpus, section 10.2).
* `README.md` — devices, wiring, legacy status-frame table, debugging hints, external
  protocol references (klotztech VBMS wiki, imval/AntBMS, RoboDurden/AntBms-Arduino).