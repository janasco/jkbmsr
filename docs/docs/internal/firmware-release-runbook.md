# Firmware Release Runbook

Use this runbook when publishing a production firmware update for JKBMSR.

## Before Tagging

1. Confirm the source version in `include/FirmwareVersion.h`.
2. Build firmware locally.
3. Compile firmware tests locally.
4. Review release notes and rollback target.

## Release

1. Push the current `main` branch.
2. Create a tag matching the source version:

   ```text
   firmware-v<version>
   ```

3. Push the tag.
4. Run `firmware/scripts/release.sh` from a machine that has the Cloudflare
   credentials and the OTA signing key exported. There is no CI to do this for
   you; see `DEPLOY.md` at the root of this repository.
5. Verify:
   - R2 object upload
   - D1 latest firmware metadata
   - GitHub release assets
   - `/api/v1/ota/latest`
   - authenticated firmware download headers

## If Something Fails

1. Stop further release tags.
2. Roll back the D1 latest pointer to the previous good version.
3. Record the failure mode before attempting a fixed release.
