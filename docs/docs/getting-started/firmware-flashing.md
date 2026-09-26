# Firmware Flashing

Flash the ESP32 gateway over USB. Prefer the browser flasher when you have a
published release that includes Wi‑Fi provisioning (`0.1.4+`).

## Browser (recommended for published releases)

1. On a desktop **Chrome** or **Edge** machine, open
   [cdn.jkbmsr.com/flash](https://cdn.jkbmsr.com/flash).
2. Connect the ESP32 with a USB **data** cable; close any serial monitors.
3. Click **Connect and install**, pick the port, wait for the flash to finish.
4. When the dialog offers Wi‑Fi setup (**Improv Serial**), enter the home SSID
   and password. Keep USB connected.
5. On success the browser opens
   [app.jkbmsr.com/onboard](https://app.jkbmsr.com/onboard) with device ID +
   claim code — sign in and claim.

Field fallback (no USB): hold **BOOT** ~5s, join SoftAP `JKBMSR-Setup-XXXX`
(password = claim code), submit Wi‑Fi from a phone.

## Local PlatformIO (dev boards / pre-release)

Use this when the CDN build is older than provisioning, or you are testing
`main` before tagging a release:

```bash
cd jkbmsr-firmware
pio run -e dev -t upload
pio device monitor -b 115200
```

Then either:

- Re-open [cdn.jkbmsr.com/flash](https://cdn.jkbmsr.com/flash), connect, and use
  the install dialog’s Wi‑Fi / logs path if Improv is detected, **or**
- Watch serial for the SoftAP name + claim code and provision from a phone.

Encrypted prototypes: see `jkbmsr-firmware/docs/secure-bringup.md`
(`pio run -e idf-secure -t upload`).

## Safety

Disconnect the JK-BMS UART cable while flashing if you are unsure about wiring.
Do not power the ESP32 directly from battery pack voltage.
