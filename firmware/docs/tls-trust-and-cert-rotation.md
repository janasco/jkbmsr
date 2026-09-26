# TLS Trust & Certificate Rotation

The firmware talks to `api.jkbmsr.com` over HTTPS and **verifies the server
certificate chain** before sending device credentials or telemetry. This
replaces the previous `WiFiClientSecure::setInsecure()` calls, which accepted
any certificate and left every connection open to a trivial man-in-the-middle
(a rogue AP, ARP spoofing on a shared network, or a compromised router — all
realistic for the RV / off-grid / shared-site deployments this product
targets).

## How verification works

- The device trusts a bundle of public root CAs (Mozilla's set, as published
  by the curl project, plus the pinned roots in `data/cert/extra-roots.pem`),
  embedded into flash at build time.
- On each TLS connection, `WiFiClientSecure` validates the presented chain via
  ESP-IDF's `esp_crt_bundle`. **Its trust rule is stricter than a browser's:
  the issuer of the top certificate the server presents must be in the
  bundle.** If Cloudflare serves a root cross-signed by an older CA (as it
  does today: GTS Root R4 cross-signed by GlobalSign Root CA), the older CA is
  the one that must be present — having the newer root alone is not enough,
  even though desktop `openssl verify` will report OK in that situation. Use
  `scripts/verify-device-trust.sh` to check trust the way the device does.
- After Wi-Fi connects, firmware synchronizes UTC using NTP before attempting
  HTTPS. Certificate validity checks fail against an ESP32's default 1970
  clock even when the root chain is trusted; cloud calls remain deferred and
  the clock/auth bootstrap retries every 30 seconds until successful.
- Configuration lives in exactly one place: `src/net/SecureClient.cpp`
  (`configureSecureClient()`), called by every cloud/OTA client.

Files:

- `data/cert/cacert.pem` — human-auditable source (the root certs, PEM).
- `data/cert/extra-roots.pem` — pinned roots appended to the Mozilla set:
  roots Mozilla has retired that production chains still require. Currently
  GlobalSign Root CA (R1), removed by Mozilla in 2026 but still the
  cross-signer of the GTS Root R4 certificate Cloudflare serves (expires
  2028-01-28 — revisit before then).
- `data/cert/x509_crt_bundle.bin` — the indexed binary actually embedded
  (generated from `cacert.pem`; keeps only an index in RAM, ~56 KB flash).
- `scripts/regenerate-ca-bundle.sh` — regenerates both from the current
  upstream Mozilla export plus `extra-roots.pem`, then runs the device-trust
  check below.
- `scripts/verify-device-trust.sh` — validates a live host the way
  `esp_crt_bundle` does (top presented cert's issuer must be a bundle root).
- `platformio.ini` → `board_build.embed_files` — embeds the bundle; the linker
  symbol `_binary_data_cert_x509_crt_bundle_bin_start` is derived from the
  file path, so **do not move the bundle** without updating
  `SecureClient.cpp`.

## Why the full Mozilla bundle, not a pinned CA

Pinning a single CA (or leaf) is a smaller trust surface but is operationally
dangerous: Cloudflare rotates edge certificates frequently and can switch the
issuing CA. A device pinned to the wrong CA would fail every connection until
it is physically reflashed — a **fleet-wide outage with no remote recovery**.
The full public-root bundle survives those rotations. Narrowing the trust set
to only the CAs Cloudflare uses is a reasonable future hardening step, but only
once there is a safe remote-recovery path.

As of this writing, `api.jkbmsr.com` chains:

```
leaf (CN=jkbmsr.com)
  → Google Trust Services "WE1"
  → GTS Root R4 (cross-signed by GlobalSign Root CA)
```

The top presented certificate is the cross-signed GTS Root R4, so the root the
device actually needs is `GlobalSign Root CA` (R1) — supplied via
`extra-roots.pem` since Mozilla's 2026 removal. Firmware ≤ 0.1.6 shipped a
bundle without it, which made every handshake fail with
`esp_crt_bundle: Failed to verify certificate` (X509 error -12288) even with a
correct clock.

## Runbook: devices fail to connect after a Cloudflare cert change

Symptom: devices that were online start failing to reach the API, logs show
TLS/handshake failures, and the change lines up with a certificate rotation.

1. Check what the host now chains to:
   ```bash
   echo | openssl s_client -connect api.jkbmsr.com:443 -servername api.jkbmsr.com -showcerts 2>/dev/null | grep -E "^ *[0-9]+ s:|^ *i:"
   ```
2. Confirm whether the chain validates **the way the device validates it**:
   ```bash
   ./scripts/verify-device-trust.sh api.jkbmsr.com data/cert/cacert.pem
   ```
   Do **not** rely on `openssl s_client -CAfile` / `openssl verify` alone:
   they accept a chain whenever any presented certificate matches a trust
   anchor by subject+key, while `esp_crt_bundle` requires the top presented
   certificate's *issuer* to be in the bundle. The two disagree exactly when
   Cloudflare serves a cross-signed root (the 0.1.6 outage).
3. If the device-trust check fails, add the missing root to
   `data/cert/extra-roots.pem` (with fingerprint provenance) if it is not in
   the Mozilla set, then refresh the bundle and ship an OTA update:
   ```bash
   ./scripts/regenerate-ca-bundle.sh   # regenerates + re-runs the check
   pio run                             # rebuild with the new bundle
   ```
   Then cut a new firmware release through the normal signed-OTA pipeline.

> Note: a device that cannot complete the TLS handshake also cannot pull an
> OTA update (OTA runs over the same verified HTTPS path). This is the reason
> to keep the trust set broad enough to tolerate routine CA rotation — so this
> runbook is a "refresh and roll forward" task, not a "recall the hardware"
> emergency.
