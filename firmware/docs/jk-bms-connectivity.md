# JK-BMS Connectivity (Bluetooth)

The gateway supports every JK-BMS model with software version >= 6.0 over
Bluetooth (BLE). There is no wired UART transport.

## BLE (JK02 protocol)

Enabled on every build; configured via remote config:

```json
{ "bmsBleAddress": "aa:bb:cc:dd:ee:ff" }
```

Leave `bmsBleAddress` empty to auto-discover the strongest nearby device that
advertises the JK service or a JK-prefixed Bluetooth name. Set an address when
more than one JK-BMS is in range and deterministic selection is required.

The client connects to service `0xFFE0` / characteristic `0xFFE1`, requests
device info (command `0x97`) to read the hardware version, auto-selects the
24S (< 11) or 32S (>= 11) frame layout, then polls cell info (command `0x96`).
Telemetry reads need no BMS app password. BLE reports MOS temperature at
0.1 °C resolution, balancing current, state of health, and per-cell data for
up to 32 cells.

The connection is read-only: the gateway only reads telemetry and never writes
to the battery.

## Partition note (0.2.0)

The BLE stack (NimBLE) pushed the image past the stock 1.25MB OTA slots, so
0.2.0 moves to `partitions-4mb-ota.csv` (1.92MB slots, same nvs/otadata/app0
offsets). Devices flashed before 0.2.0 must be re-flashed once over USB/Web
Serial — an OTA from 0.1.x will refuse the oversized image (the device stays
on its current firmware; nothing bricks). Provisioning data in NVS survives
the reflash because the NVS offset is unchanged (do not use "erase device").
