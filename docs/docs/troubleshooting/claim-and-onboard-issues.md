# Claim and onboard issues

Problems claiming a gateway after browser flash or SoftAP setup.

## Claim returns “Invalid device credentials”

Usually the gateway has not registered with the cloud yet (Wi‑Fi just joined).

1. Keep the gateway powered and on the target Wi‑Fi.
2. Retry claim — the onboard form polls for about 90 seconds.
3. If it still fails, open a serial monitor at 115200 and confirm the device ID / claim code match the form.
4. Confirm production firmware is `0.1.4` or newer (claim-code path).

Wrong claim code or typo also returns the same generic 401 — double-check the code from the label or serial log.

## Claim blocked: verify your email

If production has email verification enabled, claim returns 403 until the address is verified.

1. Open the verification link from the registration email.
2. Sign in again (prefer the same browser that started onboard).
3. Return to `/onboard?device=…&code=…` or Devices → Claim.

## Device already claimed (409)

The device is bound to another account. Use factory reset on the gateway (long BOOT hold) only if you own the hardware, then claim again from the intended account.

## Onboard deep link lost after login/register

The flasher sends you to `/onboard?device=…&code=…`. Auth should preserve that via `?next=` and session storage.

If the link is lost:

1. Re-open the URL from the flasher success screen, or
2. Enter device ID + claim code manually at [app.jkbmsr.com/devices/claim](https://app.jkbmsr.com/devices/claim).

## SoftAP works but claim fails

Captive portal only configures Wi‑Fi. The device must still reach `api.jkbmsr.com` on the customer network (outbound HTTPS). Captive portals that block unknown hosts will prevent register/claim.

## Related

- [First device setup](/getting-started/first-device-setup)
- [WiFi issues](/troubleshooting/wifi-issues)
- [Telemetry issues](/troubleshooting/telemetry-issues)
