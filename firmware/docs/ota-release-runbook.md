# OTA Release Runbook

> **This runbook describes the old CI-driven flow and is kept for reference.**
> This repository no longer uses GitHub Actions, so the "watch the workflow"
> steps below no longer apply. The current, hand-run procedure is
> [`manual-release-runbook.md`](manual-release-runbook.md), which is performed
> by `scripts/run-checks.sh` and `scripts/release.sh`. Where the two disagree,
> the manual runbook is the current one.

This runbook is for maintainers releasing production firmware from `jkbmsr-firmware`.

## Preconditions

- `include/FirmwareVersion.h` contains the intended release version.
- `PLATFORMIO_CORE_DIR=/tmp/platformio pio run` succeeds locally.
- `PLATFORMIO_CORE_DIR=/tmp/platformio pio test -e dev --without-uploading` succeeds locally.
- Cloudflare secrets are configured in the repository.
- OTA signing secrets are configured in the repository.
- The change log and release notes are reviewed before tagging.

## Release Flow

1. Confirm the firmware version in source matches the intended tag.
2. Build and compile tests locally.
3. Push the current `main` branch.
4. Create a tag in the format `firmware-v<version>`.
5. Push the tag to GitHub.
6. Watch the `Release firmware OTA` workflow.
7. Confirm the workflow uploads:
   - firmware binary
   - SHA-256 checksum
   - signed OTA metadata
   - signed OTA bundle verification
   - R2 object
   - D1 firmware metadata
   - GitHub release assets
   - optional `jkbmsr-releases` public artifact mirror
   - public release-history index validation when mirroring is enabled
8. Verify `GET /api/v1/ota/latest` returns the new version and signature metadata.
9. Verify an authenticated `GET /api/v1/ota/firmware/:firmwareId` returns the expected checksum header.
10. Verify the public release repository mirrors the same version if cross-repo publishing is enabled.
11. Record any release issues in the release notes before leaving the release window.

## Commands

```bash
PLATFORMIO_CORE_DIR=/tmp/platformio pio run
PLATFORMIO_CORE_DIR=/tmp/platformio pio test -e dev --without-uploading
./scripts/test-production-ota.sh
./scripts/test-hardware-ota-smoke.sh
git tag firmware-v<version>
git push origin firmware-v<version>
```

## Release Secrets

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `OTA_SIGNING_PRIVATE_KEY_B64`
- `OTA_SIGNING_KEY_ID`
- Optional: `RELEASES_REPO_PUSH_TOKEN`

## Real Hardware Validation

When a USB-connected ESP32 is available, run the hardware smoke test after the release completes:

```bash
./scripts/test-hardware-ota-smoke.sh
```

If the board has already registered and you have its device credentials, include them so the script can authenticate and poll the live OTA endpoint:

```bash
DEVICE_ID=<device-id> DEVICE_SECRET=<device-secret> ./scripts/test-hardware-ota-smoke.sh
```

Blank-board and provisioned-board run modes are documented in:

```text
docs/hardware-ota-smoke-test.md
```

## TODO

- Validate OTA end-to-end on a real ESP32 using the signed `0.1.5` production
  release path (Improv provision → claim → telemetry → OTA). Hardware arrives
  after this release; see `docs/first-device-bringup.md`.

## Guardrails

- Do not retag an existing version.
- Do not overwrite a released firmware object.
- Do not push a release tag without verifying the source version first.
- Keep releases limited to JK-BMS support in version 1.
- Do not publish private signing keys into the public release repository.
- Keep the generated public release-history index and manifest files aligned with the signed production metadata.
