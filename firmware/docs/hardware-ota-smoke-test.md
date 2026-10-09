# Hardware OTA Smoke Test

Use this runbook when a real ESP32 gateway is attached to the maintainer workstation over USB.

This is a smoke test, not a full factory provisioning flow.

## When To Use It

Run this after:

- a production firmware release
- a major OTA change
- a device bootstrap change
- a WiFi or registration flow change

## Prerequisites

- ESP32 connected over USB
- serial port visible as `/dev/ttyUSB*` or `/dev/ttyACM*`
- PlatformIO installed
- network access to `https://api.jkbmsr.com`

## Machine-Side Preflight

Run this first on the maintainer workstation before attaching hardware:

```bash
./scripts/check-hardware-ota-prereqs.sh
```

This verifies:

- required local tools exist
- a likely ESP32 serial device is visible if hardware is already attached
- the expected smoke-test scripts are present

For a production-cloud OTA sanity check without hardware, use:

```bash
./scripts/test-production-ota.sh
```

That script verifies the live OTA metadata, signature, and authenticated download path from this machine, but it does not prove flashing or on-device reboot behavior.

Command:

```bash
./scripts/test-hardware-ota-smoke.sh
```

## Blank Board Flow

Use this for a board that has not been claimed yet (firmware `0.1.4+`).

1. Connect the board over USB.
2. Run:

```bash
./scripts/test-hardware-ota-smoke.sh
```

3. Confirm the script:
   - flashes the current build
   - captures the reboot log
   - finds `JKBMSR firmware starting`
4. Let the board boot. Capture from serial:
   - `deviceId`
   - claim code
   - SoftAP password — printed as `SoftAP password: …`, derived per device from
     the claim code (there is no shared setup password any more)
5. Join Wi‑Fi (Improv or SoftAP), then claim at
   `https://web.jkbmsr.com/onboard?device=…&code=…`.
6. For authenticated OTA checks after claim/login, set
   `DEVICE_ID` + `DEVICE_SECRET` (from register response / NVS) or
   `DEVICE_TOKEN` and re-run with `FLASH_CURRENT_BUILD=0`.

Blank-board smoke testing proves:

- flashing still works
- the board boots
- serial logging is intact
- claim code is printed

Blank-board smoke testing does not yet prove:

- authenticated OTA polling
- release download
- OTA application

Machine-side claim-code API check (no hardware):

```bash
./scripts/test-production-claim.sh
```

Machine-side OTA signature/download check:

```bash
./scripts/test-production-ota.sh
```
## Provisioned Board Flow

Use this for a board that already has valid JKBMSR device credentials.

1. Connect the board over USB.
2. Run:

```bash
DEVICE_ID=<device-id> DEVICE_SECRET=<device-secret> ./scripts/test-hardware-ota-smoke.sh
```

3. Confirm the script:
   - flashes the current build
   - captures the reboot log
   - finds `JKBMSR firmware starting`
   - logs into the production device API
   - polls `GET /v1/ota/latest`

You can also provide an already issued device token:

```bash
DEVICE_TOKEN=<device-jwt> ./scripts/test-hardware-ota-smoke.sh
```

Provisioned-board smoke testing proves:

- the board still flashes and boots
- device credentials are accepted by production
- the board can reach the live OTA metadata endpoint

## Current Limitation

This smoke test does not yet execute a full OTA apply-and-reboot cycle on the board.

That remains a follow-up task for real hardware validation.
