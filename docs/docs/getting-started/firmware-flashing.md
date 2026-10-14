# Firmware Flashing

Flash the ESP32 gateway over USB. All flashing happens in the browser flasher at
<https://web.jkbmsr.com/flash> — it requires a signed-in JK BMS Remote account.
There is no local flashing option; PlatformIO builds are for firmware
development only, never for customer installs.

## Browser flasher

1. Sign in at <https://web.jkbmsr.com>, then on a desktop **Chrome** or
   **Edge** machine open the flasher at
   [web.jkbmsr.com/flash](https://web.jkbmsr.com/flash). Firmware is fetched from the
   authenticated JK BMS Remote API, not a public CDN.
2. Connect the ESP32 with a USB **data** cable; close any serial monitors.
3. Click **Connect and install**, pick the port, wait for the flash to finish.
4. When the dialog offers Wi‑Fi setup (**Improv Serial**), enter the home SSID
   and password. Keep USB connected.
5. On success the browser opens
   [web.jkbmsr.com/onboard](https://web.jkbmsr.com/onboard) with device ID +
   claim code — sign in and claim.

Field fallback (no USB): hold **BOOT** ~5s, join SoftAP `JKBMSR-Setup-XXXX`
(password = claim code), submit Wi‑Fi from a phone.

## Safety

Keep the gateway clear of high-current battery wiring while flashing.
Do not power the ESP32 directly from battery pack voltage.
