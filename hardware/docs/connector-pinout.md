# Connector Pinout Notes

JKBMSR Mini will use a JST connector for the JK-BMS communication port.

## UART Signals

The ESP32 side of this connector is fixed by `jkbmsr-firmware` (see
`devices/JK_UART_GPS_PORT/` in that repo), so the board should route to these
pins by default (remappable in firmware config, but this is the assumption
to design the JST footprint against):

| Signal | ESP32 pin | JK-BMS GPS port |
| --- | --- | --- |
| RX | GPIO16 | TX |
| TX | GPIO17 | RX |
| GND | GND | GND |

- Baud rate: 115200.
- Optional regulated power input only if the design explicitly supports it.
- Never route JK-BMS pack/VBAT voltage to the ESP32 — UART only.

## Warnings

- Do not connect battery pack voltage to the ESP32.
- Confirm the JK-BMS connector pinout before connecting hardware.
- Confirm voltage levels before connecting UART pins.
- Wrong wiring can permanently damage the ESP32 or JK-BMS.
