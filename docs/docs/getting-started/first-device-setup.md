# First device setup

End-to-end path for a new ESP32 gateway: browser flash → Wi‑Fi → claim → dashboard.

Use this for the first physical board. Encrypted / Secure Boot prototypes are a separate path (`idf-secure`); start with the public CDN build.

## What you need

- ESP32 (USB-C) and a Chrome or Edge browser
- Wi‑Fi credentials for a 2.4 GHz network
- A JK BMS Remote account at [app.jkbmsr.com](https://app.jkbmsr.com)
- Optional: JK-BMS UART wired later (claim works without BMS data)

## Happy path (CDN flash)

1. Open [cdn.jkbmsr.com/flash](https://cdn.jkbmsr.com/flash) in Chrome or Edge.
2. Connect the ESP32 over USB and flash the latest firmware (`0.1.4` or newer).
3. When Improv Serial appears, join your Wi‑Fi network on the same cable.
4. The flasher redirects to `https://app.jkbmsr.com/onboard?device=…&code=…`.
5. Sign in or create an account (the onboard URL is preserved through login/register).
6. Confirm the prefilled device ID and claim code, then **Claim device**.
7. Open the dashboard — the gateway should appear. Pack SOC/cells stay empty until UART is wired.

## SoftAP fallback

If Improv is unavailable (phone-only, field install):

1. After flash, the SoftAP `JKBMSR-Setup-XXXX` appears (password = claim code).
2. Join that network and complete captive-portal Wi‑Fi setup.
3. Claim at [app.jkbmsr.com/onboard](https://app.jkbmsr.com/onboard) using the device ID and claim code from the serial log or device label.

## Serial log cues (USB monitor @ 115200)

Expect lines that include:

- Device ID
- Claim code
- SoftAP name `JKBMSR-Setup-XXXX` when Wi‑Fi is not configured
- Successful cloud register after Wi‑Fi joins

## Common races

| Symptom | Cause | What to do |
| --- | --- | --- |
| Claim says “Invalid device credentials” right after Wi‑Fi | Device has not finished `POST /device/register` yet | Keep the form open — the dashboard retries for ~90s. Or wait and claim again. |
| Claim says verify your email (403) | Email verification is enabled in production | Open the verification link, then sign in (return path is preserved when possible). |
| Device online, SOC 0%, no cells | Claim succeeded; BMS UART not wired or BMS asleep | Wire UART, check baud/pins in device settings. |
| Redirect lost after register | Opened verify email on another device | Sign in on the original browser, or reopen the onboard URL from the flasher. |

## After claim

1. Confirm the device row on [app.jkbmsr.com/dashboard](https://app.jkbmsr.com/dashboard).
2. Wire JK-BMS UART (see [JK-BMS wiring](/getting-started/jk-bms-wiring) and [UART pinout warnings](/getting-started/uart-pinout-warnings)).
3. Confirm live telemetry and optional OTA from device settings.

## Related

- [ESP32 gateway setup](/getting-started/esp32-gateway-setup)
- [Firmware flashing](/getting-started/firmware-flashing)
- [Device registration](/getting-started/device-registration)
- [Claim and onboard issues](/troubleshooting/claim-and-onboard-issues)
- [WiFi issues](/troubleshooting/wifi-issues)
- [Telemetry issues](/troubleshooting/telemetry-issues)
