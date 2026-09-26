# Phase 2 — Encryption at rest (H6), development mode

Implements H6 (see `docs/hardware-security-hardening-plan.md`). Goal: WiFi
credentials, device secret, JWT, and claim code in NVS are **not recoverable
from a flash dump**, while keeping the existing Arduino application code.

**Build approach:** migrate to **Arduino as an ESP-IDF component**
(`framework = arduino, espidf`) so flash encryption, NVS encryption, and
Secure Boot v2 are real `sdkconfig` options — not hand-patched Arduino
prebuilts.

**Mode:** **Development** only in this phase. UART download and re-flash stay
available. **No Release-mode eFuse burns.** Those are Phase 3 (manufacturing).

**Phase 1 prerequisite:** done (Improv Serial + SoftAP + claim code + reset).

---

## Target end state (dev boards)

```
plain Arduino env:dev  ──(keep as CI fallback until idf is default)──►
                              │
env:idf (arduino+espidf)  ──► flash encryption (DEVELOPMENT)
                              NVS encryption (keys in nvs_keys partition)
                              Secure Boot v2 signed images (ECO3+ chips)
                              OTA still applies under encryption
```

Existing already-flashed field units are **not** retroactively encrypted; this
is a new image / new hardware bring-up path.

---

## Tasks

| ID | Task | New/changed files | Effort | Depends on |
|---|---|---|---|---|
| P2-0 | Arduino-as-IDF component build (`env:idf`) green | `CMakeLists.txt`, `src/CMakeLists.txt`, `sdkconfig.defaults`, `platformio.ini` | 2d | — |
| P2-1 | Custom partition table + `nvs_keys` | `partitions-secure.csv`, sdkconfig | 0.5d | P2-0 |
| P2-2 | Flash encryption DEVELOPMENT mode | `sdkconfig.defaults.secure`, `env:idf-secure`, docs | 1d | P2-1 |
| P2-3 | NVS encryption (flash-enc key scheme) | sdkconfig, ConfigStore smoke notes | 1d | P2-2 |
| P2-4 | Secure Boot v2 signed build (dev keys) | `keys/` (gitignored private), sdkconfig | 1.5d | P2-0 |
| P2-5 | OTA under encryption end-to-end | docs + hardware checklist | 1.5d | P2-2, P2-3 |
| P2-6 | Make `env:idf` the default CI build; keep `env:dev` optional | `platformio.ini`, workflows | 0.5d | P2-0..P2-3 |
| P2-7 | Bring-up / recovery runbook | `docs/secure-bringup.md` | 1d | P2-2..P2-5 |

Critical path: **P2-0 → P2-1 → P2-2 → P2-3 → P2-5**. P2-4 (Secure Boot) can
proceed in parallel once P2-0 is green, but on classic ESP32 it requires
**ECO3 (rev ≥ 3.0)** — confirm silicon before enabling on a given board.

---

### P2-0 — Arduino-as-IDF component build
- Add root `CMakeLists.txt` + `src/CMakeLists.txt` registering every firmware
  `.cpp` and include dirs (`src/`, `include/`).
- Add `sdkconfig.defaults` with `CONFIG_AUTOSTART_ARDUINO=y` (and any FreeRTOS
  tick / mbedTLS knobs we already rely on).
- New PlatformIO env `env:idf`: `framework = arduino, espidf`, same board,
  same `lib_deps`, same monitor speed.
- Keep `env:dev` (`framework = arduino`) as the default until P2-6 so CI and
  the public flasher path stay stable.
- Embed the CA bundle via `target_add_binary_data` for the IDF path; keep the
  existing `board_build.embed_files` symbol for `env:dev` (dual-symbol shim in
  `SecureClient.cpp`).
- **Accept:** `pio run -e idf` links a flashable image under ~60% of the
  secure app slot; `pio run -e dev` still green; unit tests still compile on
  `env:dev`.
- **Host note:** ESP-IDF's PlatformIO builder needs a working `python3 -m venv`
  (Debian: `python3-venv`). CI images usually have this; bare hosts may need
  it installed before the first `env:idf` build.

### P2-1 — Partition table with `nvs_keys`
- Custom CSV: `nvs`, `nvs_keys` (for NVS encryption keys), `otadata`,
  `app0`/`app1` (OTA), sized so the current ~82% image still fits with headroom.
- Wire via `board_build.partitions` / `CONFIG_PARTITION_TABLE_CUSTOM`.
- **Accept:** clean flash map; first boot creates empty encrypted-capable NVS
  layout without bricking.

### P2-2 — Flash encryption (DEVELOPMENT)
- `CONFIG_SECURE_FLASH_ENC_ENABLED=y`
- `CONFIG_SECURE_FLASH_ENCRYPTION_MODE_DEVELOPMENT=y`
- Device-generated key on first boot (recommended in the hardening plan).
- Document: first boot after enabling will encrypt in place and reset; UART
  re-flash of *plaintext* still works in development mode.
- **Accept:** `espefuse` shows encryption enabled in development; `esptool`
  read of app/NVS regions is ciphertext; device still boots and provisions.

### P2-3 — NVS encryption
- `CONFIG_NVS_ENCRYPTION=y` with flash-encryption-protected key partition.
- Confirm `Preferences` / `ConfigStore` round-trip of wifi + claim code + JWT
  after a reboot.
- **Accept:** dumping the NVS partition does not yield plaintext SSID/password
  or device secret.

### P2-4 — Secure Boot v2 (development signing)
- Generate a **dev-only** signing key (never the production OTA key); store
  private key outside git (`keys/*.pem` gitignored).
  Helper: `scripts/generate-secure-boot-dev-key.sh`.
- `env:idf-secureboot` layers `sdkconfig.defaults.secureboot` on top of the
  encryption defaults; uses `partitions-secureboot.csv` (table @ 0xD000).
- `CONFIG_SECURE_BOOT=y`, `CONFIG_SECURE_BOOT_V2_ENABLED=y`,
  `CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y`.
- Require `CONFIG_ESP32_REV_MIN_3=y` (ECO3). Skip / document for older revs.
- **Accept:** `pio run -e idf-secureboot` produces signed bootloader,
  partitions, and `firmware-signed.bin`.

### P2-5 — OTA under encryption
- Run the existing OTA path (signed metadata + binary) on a flash-encrypted
  device; confirm `Update` writes correctly and anti-rollback still holds.
- **Accept:** checklist in `docs/secure-bringup.md` signed off on one
  prototype.

### P2-6 — CI builds the IDF / secure images
- Keep `default_envs = dev` (and the OTA release artifact path) until P2-5
  hardware sign-off.
- `scripts/run-checks.sh` also builds `idf`, `idf-secure`, and
  `idf-secureboot` (ephemeral dev signing key).
- **Accept:** `scripts/run-checks.sh` is green for all four envs.

### P2-7 — Bring-up / recovery runbook
- First-boot encrypt sequence, how to re-flash in development mode, what
  *not* to burn for Release mode, key escrow pointers, brick recovery limits.
- Explicit **Phase 3 gate**: Release-mode eFuse burn is out of scope here.

---

## Out of scope for Phase 2
- Release-mode flash encryption / eFuse burn (Phase 3 / manufacturing).
- Host-generated flash keys (unless factory flow later requires them).
- Improv-over-BLE (still deferred; needs BLE footprint + partitions).
- Retrofitting encryption onto units already in the field via OTA alone
  (impossible without a physical re-flash + eFuse step).

## Risks
- Image size: Arduino+IDF is larger than Arduino-prebuilt; may force partition
  trim or `board_build.partitions` growth before encryption lands.
- Secure Boot v2 needs ESP32 ECO3+; many "esp32dev" modules are older — detect
  before enabling P2-4 on a given board.
- First enable of flash encryption rewrites flash and resets; do it on a
  disposable prototype first.
- Never commit production secure-boot private keys; rotate/dev vs prod keys
  must stay separate from the OTA ECDSA signing key.
