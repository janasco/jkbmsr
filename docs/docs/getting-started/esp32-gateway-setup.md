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

1. Flash firmware at [web.jkbmsr.com/flash](https://web.jkbmsr.com/flash) (sign in first).
2. Join Wi‑Fi with Improv Serial (same USB cable) or SoftAP fallback.
3. Claim the device at [web.jkbmsr.com/onboard](https://web.jkbmsr.com/onboard) with the device ID and claim code.
4. Make sure the JK-BMS is powered and within Bluetooth range of the ESP32 gateway.
5. Confirm telemetry appears in the dashboard.

Claim can succeed before the BMS link is up — empty SOC/cells until the BMS is
in range and connected is expected.
