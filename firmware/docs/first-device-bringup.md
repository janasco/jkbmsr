# First device bring-up (no prior flash)

Checklist for the first physical ESP32 once it arrives. Assumes `main` already
has Phase 1 provisioning.

Public runbook (keep this in sync): https://docs.jkbmsr.com/getting-started/first-device-setup

## Option A — CDN browser flash (`0.1.5+`)

1. Confirm `cdn.jkbmsr.com` serves firmware `0.1.5` or newer. The published
   `0.1.4` artifact was an embedded test runner and must not be used.
2. Open https://cdn.jkbmsr.com/flash in Chrome/Edge.
3. Flash → Improv Wi‑Fi → follow redirect to https://web.jkbmsr.com/onboard.

## Option B — Local flash tomorrow (works before the CDN release)

```bash
cd ~/repos/jkbmsr-firmware
pio run -e dev -t upload
pio device monitor -b 115200
```

Expect serial lines for device ID, claim code, and (if no Wi‑Fi yet) SoftAP
`JKBMSR-Setup-XXXX`. The SoftAP password is **derived from this device's claim
code** and is printed on the serial log as `SoftAP password: …` — read it from
there. There is no longer a shared setup password, so knowing the device ID
(the SSID suffix is public) is not enough to join the network. Then either:

- Use SoftAP from a phone, or
- Keep USB connected and drive Improv from the browser flasher / ESP Web Tools
  once it detects the running firmware.

Claim at https://web.jkbmsr.com/onboard?device=…&code=… (or Devices → Claim).

## Option C — Encrypted prototype (Phase 2)

Only on a disposable board:

```bash
pio run -e idf-secure -t upload
```

Follow `docs/secure-bringup.md`. Do **not** burn Release-mode eFuses.
