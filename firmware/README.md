# jkbmsr-firmware

ESP32 firmware for JKBMSR, the JK Battery Management System Remote gateway.

This repository is now in execution. It contains the PlatformIO firmware that runs on the ESP32 gateway, talks to a JK-BMS over UART, communicates with JKBMSR Cloud over HTTPS JSON APIs, and supports OTA firmware updates.

## Role In The System

`jkbmsr-firmware` is the embedded gateway layer.

It is responsible for:

- Reading JK-BMS telemetry over UART.
- Managing local device identity and configuration.
- Connecting the ESP32 to WiFi.
- Registering and authenticating with JKBMSR Cloud.
- Uploading telemetry to the cloud API.
- Fetching remote device config.
- Checking for OTA updates.
- Downloading firmware binaries securely.
- Verifying OTA firmware with SHA-256 before update.

## Current Status

- Source firmware version: see `include/FirmwareVersion.h` — don't hardcode
  it here, it goes stale immediately (this line and the "last published"
  one below both sat several releases behind actual for a while)
- PlatformIO environment: `dev`
- Target board: `esp32dev` (the one published via OTA — see below)
- Framework: Arduino on ESP32
- Also builds for `env:esp8266-nodemcu` (`board = nodemcuv2`) — a second,
  experimental, UART-only target with no BLE and no OTA (USB reflash only).
  See `docs/esp8266-nodemcu-support.md`; not part of the OTA publish path
  below, which remains ESP32-only.
- Also builds for `env:esp32-s2-4mb` (`board = esp32-s2-saola-1`) — ESP32-S2,
  experimental, UART-only (this chip has no Bluetooth radio at all, so BLE
  BMS brands/variants are unreachable on it) but keeps OTA, unlike ESP8266.
- Also builds for `env:esp32-classic-8mb` (`board = esp32dev`, 8 MB flash) —
  same chip/pins/capabilities as `env:dev`, just larger OTA app partitions
  (`partitions-8mb-ota.csv`) for boards with more flash.
- Also builds for `env:esp32-c6-4mb` (`board = esp32-c6-devkitc-1`) —
  ESP32-C6, experimental, WiFi 6 + Bluetooth 5.3 + OTA. This is the only
  target that pins a different platform source: the official PlatformIO
  espressif32 platform has no Arduino-framework board defs for this chip at
  all (only `espidf`), so this env points at the community `pioarduino`
  fork instead, and pulls in a newer Arduino-ESP32 core (3.3.11) as a
  result — every other target still builds against the official platform's
  older core. That newer core changed a few APIs shared code touches
  (NimBLE-Arduino's scan-result types, `NetworkClientSecure::setCACertBundle`'s
  signature, mbedtls's `_ret`-suffixed function names); each is handled with
  a `#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)`
  or equivalent NimBLE-version guard, not a fork of the file. Both platforms
  register under the same PlatformIO platform name ("espressif32"), so
  installing both into one shared `~/.platformio` overwrites whichever was
  installed first — confirmed locally the hard way. `scripts/run-checks.sh`
  keeps this target in its own PlatformIO core directory specifically to
  avoid that; a local machine
  building both this env and any other in the same PlatformIO core dir back
  to back will need to let the affected packages reinstall in between.
- Latest built artifact: `.pio/build/dev/firmware.bin`
- Last published OTA version: see `jkbmsr-releases`' `firmware/latest.json`
- Production OTA publish path:
  - Tag format: `firmware-v<version>`
  - R2 object format: `firmware/jkbmsr-<version>.bin`
  - Metadata signature algorithm: `ecdsa-p256-sha256`
  - Public artifact mirror: `jkbmsr-releases`

## Tech Stack

- ESP32
- PlatformIO
- Arduino framework
- C++
- UART for JK-BMS communication
- HTTPS REST APIs
- JSON payloads
- NVS/Preferences for local config
- OTA update support
- ArduinoJson

## Repository Layout

```text
include/
  AppConfig.h
  BatteryTelemetry.h
  FirmwareVersion.h
src/
  bms/          JK-BMS UART parsing
  cloud/        Device registration, telemetry, remote config clients
  config/       NVS-backed configuration storage
  debug/        Serial logging helpers
  device/       Device identity and metadata
  network/      WiFi connection management
  ota/          OTA check, download, verification, update flow
  main.cpp      Firmware boot and runtime loop
devices/
  JK_B1A8S10P/  Per-model compatibility profile and hardware fixtures
docs/
  firmware-context.md
  hardware-ota-smoke-test.md
  ota-release-runbook.md
  ota-rollback.md
  ota-signing-public-key.pem
  public-release-distribution.md
  release-notes-template.md
scripts/
  test-hardware-ota-smoke.sh
  test-production-ota.sh
platformio.ini
```

## Cloud APIs Used

- `POST /api/v1/device/register`
- `POST /api/v1/device/login`
- `POST /api/v1/telemetry`
- `GET /api/v1/device/config`
- `GET /api/v1/ota/latest`
- `GET /api/v1/ota/firmware/:firmwareId`

Production API base URL:

```text
https://api.jkbmsr.com
```

## Build

```bash
PLATFORMIO_CORE_DIR=/tmp/platformio pio run
```

Production OTA simulation from this machine:

```bash
./scripts/test-production-ota.sh
```

USB-connected ESP32 smoke test from this machine:

```bash
./scripts/test-hardware-ota-smoke.sh
```

The firmware binary is generated at:

```text
.pio/build/dev/firmware.bin
```

## Versioning

Firmware version is defined in:

```text
include/FirmwareVersion.h
```

Current value:

```cpp
constexpr const char* kFirmwareVersion = "0.6.0";
```

## Checks And Releases

This repository does not use GitHub Actions. The build, host-test and release
workflows that used to run on every push are now two scripts you run yourself:

```bash
./scripts/run-checks.sh --dry-run     # print the plan, build nothing
./scripts/run-checks.sh               # validate profiles/targets, run the host
                                     # unit suites under ASan/UBSan, build all 25
                                     # PlatformIO environments
./scripts/release.sh <version> --dry-run
./scripts/release.sh <version> --yes  # build, sign, R2, D1, GitHub release, mirror
```

`release.sh` requires `OTA_SIGNING_PRIVATE_KEY_B64`, `CLOUDFLARE_API_TOKEN`
**and** `CLOUDFLARE_ACCOUNT_ID` to be exported, and refuses to publish without
them. Two host suites (`test_daly_d2_decoder`, `test_ks_bms_decoder`) are
documented as expected-red and are reported by name on every run.

Full procedure, required secrets, and the traps encoded in both scripts are in
[`docs/manual-release-runbook.md`](docs/manual-release-runbook.md).

## OTA Release Flow

1. Build firmware with PlatformIO.
2. Compile tests for the `dev` environment.
3. Push `main`.
4. Create and push `firmware-v<version>`.
5. Run `./scripts/release.sh <version>` — it uploads the binary and checksum,
   signs the OTA metadata, publishes to Cloudflare R2 and updates D1 metadata.
6. Deploy `releases/` to the `jkbmsr-releases` Pages project (`cdn.jkbmsr.com`).
7. Verify `GET /api/v1/ota/latest` returns the new version plus signature fields.
8. Download through the authenticated Worker endpoint and confirm SHA-256.

Generated release metadata includes:

- firmware version
- board target
- SHA-256 checksum
- signing key ID
- signature algorithm
- signed OTA metadata

## OTA Validation Paths

Use the machine-based production simulation when no physical ESP32 is attached:

```bash
FIRMWARE_VERSION=0.1.2 ./scripts/test-production-ota.sh
```

Use the hardware smoke test when an ESP32 gateway is attached over USB:

```bash
./scripts/test-hardware-ota-smoke.sh
```

Optional authenticated OTA poll for a provisioned board:

```bash
DEVICE_ID=<device-id> DEVICE_SECRET=<device-secret> ./scripts/test-hardware-ota-smoke.sh
```

The hardware smoke test does three concrete things:

1. Flashes the current PlatformIO build to the attached board.
2. Captures the reboot log and verifies the `JKBMSR firmware starting` banner.
3. Polls `GET /api/v1/ota/latest` when a device token or device credentials are provided.

Blank-board and provisioned-board procedures are documented in:

```text
docs/hardware-ota-smoke-test.md
```

## Device Identity

The device ID is a random 128-bit value generated on first boot (`DeviceIdentity::generateDeviceId()`, via `esp_random()`) and persisted in NVS — it is not derived from the WiFi MAC address. A MAC-derived ID would be guessable from public Espressif OUI ranges, letting an attacker pre-register a real device's ID before it ever boots (see `jkbmsr-api`'s `POST /device/register`, which is create-only and will reject a device whose ID is already taken). `hardwareId` (still MAC/eFuse-derived) is kept as a separate, non-authentication-relevant diagnostic field.

**Migration note:** a device that already has NVS state from firmware predating this change has never persisted a `device_id` key, so on its first boot on this firmware it will generate and persist a brand-new random ID rather than reusing its old MAC-derived one. If it was already registered/claimed in `jkbmsr-api` under the old ID, it will need to be registered and re-claimed again under the new one — the old device row and its telemetry history are not automatically migrated.

## TLS Certificate Verification

Every HTTPS connection to `api.jkbmsr.com` verifies the server certificate chain against an embedded Mozilla root-CA bundle — the firmware no longer uses `setInsecure()`. TLS setup is centralized in `src/net/SecureClient.cpp`. The trust bundle, its provenance, the regeneration script, and the runbook for a Cloudflare CA rotation are documented in [`docs/tls-trust-and-cert-rotation.md`](docs/tls-trust-and-cert-rotation.md).

## OTA Anti-Rollback

Beyond signature + SHA-256 verification, the firmware records the highest version it has ever run (NVS `fw_floor`, managed in `main.cpp`) and refuses any OTA that is not **strictly newer** than that floor — so a correctly-signed *older* release cannot be replayed to force a downgrade to a vulnerable build. Version comparison is in `src/ota/VersionCompare.cpp` (semver, fails closed on unparseable input). This changes rollback operations: to move an already-updated fleet off a bad release you must **roll forward** (publish a higher version), not re-point devices at an older one — see [`docs/ota-rollback.md`](docs/ota-rollback.md).

## Scope Rules

- JK-BMS, Daly, JBD, and Seplos are supported — selected per device via
  `bmsVendor` in device config. See `devices/README.md` for the full
  compatibility catalog and each vendor's validation-status tier.
- JK, Daly, and JBD support both UART and BLE. Seplos is **BLE only** — no
  UART parser exists for it, so Seplos devices must have `bmsBleEnabled =
  true`.
- Seplos and JBD's BLE profiles share the same service/characteristic UUIDs
  (`0xFF00`/`0xFF01`/`0xFF02`) — configure an explicit `bmsBleAddress` on
  either vendor if units from both might be advertising nearby.
- Other BMS vendors are still out of scope; do not add abstractions for
  them speculatively ahead of an actual pilot decision.
- Use HTTPS JSON APIs only.
- MQTT is intentionally out of scope.

## Next Work

Done since this was last written, removed from the list: the runtime
WiFi/auth reconnect loop (`loop()` in `main.cpp` now retries periodically
and reopens provisioning after repeated failures, rather than requiring a
reboot), WiFi provisioning UX (remote WiFi scan/change from the
dashboard, QR-code device claiming, captive portal all shipped), and
hardware-specific pin configuration (`include/HardwareProfile.h` +
`hardware-targets.json` now give every supported target — classic ESP32,
ESP32-C3, ESP32-S3, ESP8266 — its own pin defaults, capabilities, and
release pipeline instead of one fixed pin set built only for ESP32).

Still open:

- Exercise JK-BMS parser against real UART frames from more device variants
  — the UART decoder's only fixture is currently synthetic (matches the
  documented register spec, not a real capture); see
  [`devices/JK_UART_GPS_PORT`](devices/JK_UART_GPS_PORT/) for the concrete
  gap and the capture procedure. `JK_B1A8S10P`'s live bring-up already
  proved the BLE 32S decode path against real hardware, but the *committed
  regression fixture* for that layout (`kCellInfo32s`) is still synthetic —
  see [`devices/JK_B1A8S10P`](devices/JK_B1A8S10P/) for saving a real one.
- Add persistent OTA result reporting across reboot after a successful update.
- Add an idle-read timeout to the OTA download loop.
- Validate esp32-c3-4mb/esp32-s3-4mb/esp8266-uart-lite/esp32-s2-4mb/
  esp32-classic-8mb/esp32-c6-4mb on real hardware — all six build and pass
  CI but have never run on physical boards; see each target's
  `releaseStatus` in `hardware-targets.json`.
- ESP32-C2 and ESP32-H2 were evaluated and ruled out, not just deferred:
  ESP32-C2 has no Arduino framework support anywhere (not even upstream
  Arduino-ESP32 core, regardless of PlatformIO platform source), and
  ESP32-H2 has Bluetooth but no WiFi radio at all, so it can't reach
  `api.jkbmsr.com`. Neither is a "later" candidate the way C6 was.
- ESP32-C5 (dual-band WiFi + BLE) is available through the same
  `pioarduino` platform fork env:esp32-c6-4mb uses, and could be added the
  same way if there's demand for it.

See [`devices/README.md`](devices/README.md) for the full per-model
compatibility catalog and validation-status tiers (hardware-tested /
protocol-verified / synthetic-fixture-only).
