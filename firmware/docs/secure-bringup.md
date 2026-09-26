# Secure bring-up (Phase 2 — development mode)

How to flash and validate flash encryption, NVS encryption, and (optionally)
Secure Boot v2 on a **prototype** ESP32. This is **DEVELOPMENT** mode only:
UART download stays available. Release-mode eFuse burns are Phase 3 and are
irreversible — do not follow this doc for production units.

Spec: `docs/phase2-encryption-spec.md`. Plan: `docs/hardware-security-hardening-plan.md`.

## Builds

| Env | Purpose |
|---|---|
| `dev` | Pure Arduino (default, unit tests, current OTA release path) |
| `idf` | Arduino-as-IDF, **no** encryption — migration stepping stone |
| `idf-secure` | Flash encryption (DEVELOPMENT) + NVS encryption |
| `idf-secureboot` | Above + Secure Boot v2 signed images (**ESP32 ECO3+ only**) |
| `idf-s3` | Arduino-as-IDF for ESP32-S3, **no** encryption — migration stepping stone |
| `idf-secure-s3` | ESP32-S3: flash encryption (DEVELOPMENT) + NVS encryption |
| `idf-secureboot-s3` | Above + Secure Boot v2 signed images (**no chip-revision gate on S3**) |
| `idf-c3` / `idf-secure-c3` / `idf-secureboot-c3` | Same three-stage progression, ESP32-C3 (no chip-revision gate) |
| `idf-s2` / `idf-secure-s2` / `idf-secureboot-s2` | Same, ESP32-S2 — also layers `sdkconfig.defaults.no-ble` (no Bluetooth radio on this chip) |
| `idf-8mb` / `idf-secure-8mb` / `idf-secureboot-8mb` | Same, 8 MB classic-ESP32 board (same silicon/ECO3+ gate as `idf*`, just bigger flash) |
| `idf-c6` / `idf-secure-c6` / `idf-secureboot-c6` | Same, ESP32-C6 (no chip-revision gate) — **least proven**, built via the community pioarduino platform fork; confirm it actually builds in CI (job `build-c6`) before trusting it |

```bash
# Classic ESP32 — encryption only (any rev that supports flash encryption)
pio run -e idf-secure
pio run -e idf-secure -t upload   # disposable prototype only

# Classic ESP32 — encryption + Secure Boot v2 (ECO3+ required)
./scripts/generate-secure-boot-dev-key.sh
pio run -e idf-secureboot
pio run -e idf-secureboot -t upload

# ESP32-S3 — same two stages, no ECO3 gate to check
pio run -e idf-secure-s3
pio run -e idf-secure-s3 -t upload        # disposable prototype only
./scripts/generate-secure-boot-dev-key.sh # same dev key works for both chip families
pio run -e idf-secureboot-s3
pio run -e idf-secureboot-s3 -t upload

pio device monitor -b 115200
```

Host prerequisite: `python3 -m venv` must work (Debian: `python3-venv`).

## First boot after `idf-secure` / `idf-secureboot`

1. Flash completes with a **plaintext** image (development mode allows this).
2. On first reset the bootloader:
   - generates a flash-encryption key into eFuse (development-readable),
   - encrypts flash in place,
   - resets again.
3. Serial log should mention encryption / re-encrypt / restart. Wait for the
   second boot to finish before judging failure.
4. Confirm with `espefuse.py summary` (from the PlatformIO esptool package):
   `FLASH_CRYPT_CNT` / encryption-related fields show enabled, and the mode is
   still development (UART download not permanently disabled).
5. With `idf-secureboot`, also confirm Secure Boot digests are present and an
   **unsigned** image is rejected on the next flash attempt.

## Functional checklist (P2-5)

Run once per chip family you intend to manufacture — a classic-ESP32 pass
does not cover ESP32-S3 or vice versa (different flash-encryption/Secure
Boot silicon behavior, see `docs/phase3-production-hardening.md` §0).

On one encrypted prototype:

- [ ] Boots to provisioning when NVS is empty (Improv Serial and/or SoftAP)
- [ ] WiFi creds + claim code persist across reboot (`ConfigStore`)
- [ ] Device registers with claim code; `/onboard?device=&code=` claim works
- [ ] Telemetry uploads over TLS
- [ ] OTA check + apply of a newer signed build succeeds; anti-rollback still
      rejects an older floor
- [ ] `esptool.py read_flash` of the NVS region is **not** plaintext SSID/password
- [ ] (ECO3+) `idf-secureboot` boots; unsigned binary is rejected

## Recovery (development mode)

- You can still flash plaintext `idf-secure` / `idf` / `dev` over USB.
- Erasing flash (`pio run -e idf-secure -t erase`) wipes NVS; the encryption
  key in eFuse remains. Re-flash and re-provision.
- **Do not** burn Release-mode eFuses from menuconfig or `espefuse` while
  validating — that bricks UART download permanently.
- The Secure Boot **dev** PEM under `keys/` is gitignored and is **not** the
  OTA metadata signing key (see `.env.example`). Keep them separate.

## What this does *not* cover

- Release-mode flash encryption / manufacturing line procedure (Phase 3).
- Production Secure Boot key ceremony / escrow.
- Retrofitting field units already shipped without a physical re-flash.
