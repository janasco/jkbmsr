# OTA Support Checklist

Use this checklist when a device reports a failed OTA update.

## Cloud Checks

1. Confirm `/v1/ota/latest` returns the expected version.
2. Confirm the published firmware metadata record has the expected `sha256` and `target_hardware`.
3. Confirm the stored firmware object exists for the published key.
4. Confirm `GET /v1/ota/firmware/:firmwareId` returns:
   - `200 OK`
   - `X-Firmware-Version`
   - `X-Firmware-Target`
   - `X-Firmware-SHA256`

## Device Checks

1. Confirm the device has a valid token.
2. Confirm OTA is enabled in device settings.
3. Confirm the installed firmware version is older than the published version.
4. Review the device-reported OTA runtime fields:
   - last result
   - offered version
   - last check timestamp

## Decision

- If checksum headers and the stored firmware object are correct, investigate device connectivity or storage.
- If metadata is wrong, stop rollout and correct the published metadata before more devices poll.
