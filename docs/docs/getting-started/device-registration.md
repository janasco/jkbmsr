# Device Registration

Gateways self-register with JKBMSR Cloud after they join Wi‑Fi. Owners then **claim** the device with a short claim code (label, serial log, or onboard deep link).

## Device self-register

```text
POST /api/v1/device/register
```

The gateway sends its device ID, hardware ID, firmware version, and (on `0.1.4+`) a claim code. The cloud stores a hash of the claim code and returns device tokens plus config.

## Owner claim

```text
POST /api/v1/user/devices/claim
```

Authenticated customer request:

```json
{
  "deviceId": "…",
  "claimCode": "ABCD-EFGH"
}
```

- Prefer `claimCode` for all current firmware.
- Legacy `deviceSecret` is accepted only for devices registered before claim codes existed.
- If email verification is enabled, the account must be verified first (403 otherwise).
- Claiming before the device finishes register returns 401 — retry after Wi‑Fi/register completes.

Browser path: flash → Improv → [app.jkbmsr.com/onboard](https://app.jkbmsr.com/onboard)?device=…&code=….

See [First device setup](/getting-started/first-device-setup) and [Claim and onboard issues](/troubleshooting/claim-and-onboard-issues).
