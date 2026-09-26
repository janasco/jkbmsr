# JKBMSR Firmware Context

The firmware connects an ESP32 gateway to a JK-BMS over UART, reads battery data, connects to WiFi, uploads telemetry to JKBMSR Cloud, receives remote configuration, and supports OTA updates.

## Technology

- ESP32
- PlatformIO
- Arduino framework initially
- UART
- HTTPS
- JSON
- NVS storage
- OTA update support

## Modules

- `src/bms`: JK-BMS UART parser. Do not add non-JK BMS support in version 1.
- `src/network`: WiFi connection and reconnection management.
- `src/cloud`: device registration, telemetry upload, and remote config clients.
- `src/ota`: OTA update checks, firmware download, and integrity verification.
- `src/config`: NVS-backed configuration storage.
- `src/debug`: serial debug logging.

## Constraints

- Do not implement MQTT in version 1.
- Do not support Daly, JBD, Seplos, or other BMS brands in version 1.
- Do not hardcode production secrets.
- OTA updates must verify firmware integrity before applying.
