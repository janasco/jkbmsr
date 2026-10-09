# Device API

## Register

```text
POST /v1/device/register
```

Used by a new ESP32 gateway to register with JKBMSR Cloud after Wi‑Fi is configured.

Typical body fields:

| Field | Notes |
| --- | --- |
| `deviceId` | Stable gateway identifier |
| `hardwareId` | Board / chip identity |
| `firmwareVersion` | e.g. `0.1.4` |
| `claimCode` | Required on firmware `0.1.4+`; stored hashed for owner claim |

Returns device JWT / refresh material and initial config.

## Login

```text
POST /v1/device/login
```

Used by a registered ESP32 gateway to receive a fresh JWT (`deviceId` + `deviceSecret`).

## Owner claim

```text
POST /v1/user/devices/claim
```

Requires a customer Bearer token.

```json
{
  "deviceId": "esp32-…",
  "claimCode": "ABCD-EFGH"
}
```

| Status | Meaning |
| --- | --- |
| 200 | Claimed (or already owned by this user) |
| 400 | Missing `claimCode` / `deviceSecret` |
| 401 | Unknown device, wrong code, or device not registered yet |
| 403 | Email not verified (when verification is enabled) |
| 409 | Already claimed by another account |

Legacy: `deviceSecret` instead of `claimCode` only when the device has no claim-code hash (pre–claim-code registrations).

## Dashboard Device History

```text
GET /v1/dashboard/devices/:deviceId/telemetry/history
GET /v1/dashboard/devices/:deviceId/ota/history
```

Used by the authenticated dashboard to show recent telemetry trends and persistent OTA runtime events for a visible device.
