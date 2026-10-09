# Internal Release Process

Use Conventional Commits and never release broken builds.

## Firmware Releases

Firmware releases must include:

- Version
- Target hardware
- Binary
- SHA-256 checksum
- GitHub release assets
- D1 metadata update

Release flow:

1. Update `include/FirmwareVersion.h`.
2. Run the local PlatformIO build.
3. Run the local PlatformIO test compile.
4. Push `main`.
5. Create and push `firmware-v<version>`.
6. Run `firmware/scripts/release.sh`. There is no CI workflow behind this step
   any more; the operator procedure is in `DEPLOY.md` at the root of this
   repository.
7. Verify `/v1/ota/latest` and the authenticated firmware download route.

## Rollback

Rollback is a D1 metadata change. Do not overwrite released firmware objects.

Set the bad version to `is_latest = 0` and restore the previous good version to `is_latest = 1` for the same target hardware.

## Versioning Policy

- Firmware uses semantic versions.
- Cloud and web should note firmware compatibility when their release affects OTA behavior.
- Do not introduce multi-vendor abstractions in version 1.
