# ESP32 Gateway Setup

The ESP32 gateway connects your JK-BMS to JKBMSR Cloud.

For the first board, follow the full runbook: [First device setup](/getting-started/first-device-setup).

## Before You Start

- Confirm your BMS is a JK-BMS.
- Confirm the ESP32 is powered from USB-C or a safe regulated supply.
- Do not power the ESP32 directly from battery pack voltage.
- Keep wiring disconnected while checking pin labels.
- Use Chrome or Edge for the browser flasher.

## Basic Steps

1. Flash firmware at [cdn.jkbmsr.com/flash](https://cdn.jkbmsr.com/flash) (or PlatformIO for local builds).
2. Join Wi‑Fi with Improv Serial (same USB cable) or SoftAP fallback.
3. Claim the device at [app.jkbmsr.com/onboard](https://app.jkbmsr.com/onboard) with the device ID and claim code.
4. Connect the UART cable between the ESP32 gateway and JK-BMS.
5. Confirm telemetry appears in the dashboard.

Claim can succeed before UART is wired — empty SOC/cells until the BMS is connected is expected.
