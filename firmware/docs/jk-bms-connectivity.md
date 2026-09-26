# JK-BMS Connectivity (UART-TTL and BLE)

The gateway supports every JK-BMS model with software version >= 6.0, over
either link:

## UART-TTL (default)

Wired to the BMS "GPS" port (TTL UART, 115200 baud). The firmware actively
polls: it sends a `0x4E 0x57 ... 0x06` "read all registers" request each
telemetry interval and decodes the positional register response (cells, pack
voltage/current, SOC, three temperatures, cycles, capacities, warning and
status bitmasks, BMS software version). No BMS password is required — the
UART protocol is unauthenticated.

Wiring (defaults, remappable via remote config `bmsUartRxPin`/`bmsUartTxPin`/
`bmsUartBaudRate`):

| ESP32       | JK-BMS GPS port |
|-------------|-----------------|
| GPIO16 (RX) | TX              |
| GPIO17 (TX) | RX              |
| GND         | GND             |
| —           | VBAT: never connect |

## BLE (JK02 protocol)

For packs without a free UART port. Enabled via remote config:

```json
{ "bmsBleEnabled": true, "bmsBleAddress": "aa:bb:cc:dd:ee:ff" }
```

Leave `bmsBleAddress` empty to auto-discover the strongest nearby device that
advertises the JK service or a JK-prefixed Bluetooth name. Set an address when
more than one JK-BMS is in range and deterministic selection is required.

The client connects to service `0xFFE0` / characteristic `0xFFE1`, requests
device info (command `0x97`) to read the hardware version, auto-selects the
24S (< 11) or 32S (>= 11) frame layout, then polls cell info (command `0x96`).
Telemetry reads need no BMS app password. BLE additionally reports MOS
temperature at 0.1 °C resolution, balancing current, state of health, and
per-cell data for up to 32 cells.

Only one link is active at a time: BLE when configured, UART otherwise.
Falling back is a config change, not a reflash.

## Partition note (0.2.0)

The BLE stack (NimBLE) pushed the image past the stock 1.25MB OTA slots, so
0.2.0 moves to `partitions-4mb-ota.csv` (1.92MB slots, same nvs/otadata/app0
offsets). Devices flashed before 0.2.0 must be re-flashed once over USB/Web
Serial — an OTA from 0.1.x will refuse the oversized image (the device stays
on its current firmware; nothing bricks). Provisioning data in NVS survives
the reflash because the NVS offset is unchanged (do not use "erase device").
