# OTA Validation

JK BMS Remote uses two different OTA validation paths:

1. machine-based validation from a workstation
2. hardware validation with a USB-connected ESP32 gateway

Use both paths. They prove different parts of the system.

## Machine-Based Validation

Machine-based validation runs from the maintainer workstation and exercises the live production API without requiring a physical ESP32.

Use it to verify:

- device registration
- device JWT issuance
- `GET /v1/ota/latest`
- OTA metadata signature verification
- authenticated firmware download
- SHA-256 checksum verification

Current command from `jkbmsr-firmware`:

```bash
FIRMWARE_VERSION=0.1.2 ./scripts/test-production-ota.sh
```

This script simulates an older device version so production should offer the current signed release.

Use machine-based validation when:

- no ESP32 is attached to the workstation
- release automation just finished and you need a fast production check
- you want to verify signing and download integrity before touching hardware

Machine-based validation does not prove:

- USB flashing
- board boot after flash
- WiFi connection on the real gateway
- OTA application and reboot behavior on the ESP32 itself

## Hardware Validation

Hardware validation runs with a real ESP32 connected over USB to the workstation.

Current command from `jkbmsr-firmware`:

```bash
./scripts/test-hardware-ota-smoke.sh
```

The hardware smoke test currently automates:

- USB serial-port detection
- PlatformIO flash of the current build
- boot-log capture
- startup banner verification
- optional live OTA polling when device credentials are available

To let the script poll the production OTA endpoint for a provisioned board:

```bash
DEVICE_ID=<device-id> DEVICE_SECRET=<device-secret> ./scripts/test-hardware-ota-smoke.sh
```

You can also supply an already issued device JWT:

```bash
DEVICE_TOKEN=<device-jwt> ./scripts/test-hardware-ota-smoke.sh
```

Use hardware validation when:

- you need to confirm the board still flashes and boots
- you want to observe serial logs after a release
- you want a real gateway smoke test before handing hardware to an installer or customer

## Blank Board Versus Provisioned Board

Blank board:

- use `./scripts/test-hardware-ota-smoke.sh`
- verify flash success and boot banner first
- capture the assigned device credentials before expecting authenticated OTA checks

Provisioned board:

- use `DEVICE_ID=<device-id> DEVICE_SECRET=<device-secret> ./scripts/test-hardware-ota-smoke.sh`
- verify flash success, boot banner, production login, and live OTA metadata polling

The current hardware smoke test does not yet execute a full OTA apply-and-reboot cycle on the ESP32.

## Recommended Release Order

After publishing a production firmware release:

1. run machine-based validation first
2. confirm signed metadata, checksum, and authenticated download
3. run hardware validation on a USB-connected ESP32
4. record any issues in the release notes or support checklist

## Important Limits

- Do not treat machine-based validation as proof that the ESP32 can apply the update.
- Do not treat hardware flash success as proof that OTA signing metadata is correct.
- Do not expose device secrets, JWTs, or private signing keys in terminal logs or documentation.
