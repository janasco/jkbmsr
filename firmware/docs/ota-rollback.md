# OTA Rollback

Use this runbook if a released firmware version should no longer be the production OTA target.

> **Anti-rollback is enforced on-device.** Firmware records the highest version
> it has ever run (NVS `fw_floor`) and refuses any OTA that is not *strictly
> newer* than that floor — even a correctly-signed older release. This blocks
> forced-downgrade/replay attacks, but it also means **you cannot pull an
> already-updated fleet back to an older version over OTA.** Flipping
> `is_latest` to an older release only affects devices that have **not yet**
> taken the bad update. See "Rolling back devices that already updated" below.

## Immediate Response

1. Stop creating new release tags until the issue is understood.
2. Identify the last known good firmware version and checksum.
3. Confirm the corresponding R2 object and GitHub release assets still exist.

## Rollback Method (stops further spread of a bad release)

Rollback is a metadata change, not an object overwrite.

1. Set the bad release `is_latest = 0` in D1.
2. Set the last known good release `is_latest = 1` for the same `target_hardware`.
3. Verify `GET /v1/ota/latest` returns the good version again.
4. Confirm the firmware download endpoint still serves the expected checksum.

This immediately prevents any device that has not yet updated from taking the
bad release.

## Rolling back devices that ALREADY updated (roll forward)

Because of anti-rollback, devices already on the bad version will reject the
older "good" version. To fix them, **publish a new release with a higher
version number** containing the fixed (or reverted) code — a "roll forward."
The higher version clears the anti-rollback floor and installs normally.

Example: bad release is `0.1.4`; ship the fix as `0.1.5` (even if `0.1.5` is
functionally `0.1.3`'s code). Do not try to re-point devices at `0.1.3`.

## Rules

- Do not replace the binary at an existing released object key.
- Do not delete evidence of a bad release during incident response.
- Keep the SHA-256 checksum attached to every version involved in the rollback.

## Follow-Up

After rollback:

1. Document the failure cause.
2. Decide whether a fixed forward release is required.
3. Add a test, validation rule, or release guard to prevent recurrence.
