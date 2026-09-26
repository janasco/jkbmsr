# Phase 1 — WiFi Provisioning: firmware task spec

Implements H7 (see `docs/hardware-security-hardening-plan.md`). Goal: a device
with **no stored WiFi credentials** must let a non-technical user get online
without a serial monitor or a pre-baked build — driven from the browser flasher
we already ship (`cdn.jkbmsr.com/flash`), with a field fallback.

**Transport:** **Improv Serial** as primary (works over the same USB/Web-Serial
that ESP Web Tools just flashed over — no BLE stack, no partition change),
**SoftAP captive portal** as the field fallback. Improv-over-BLE is deferred.

**No eFuse / no irreversible steps in this phase.** Pure firmware + one
cross-repo backend change for the claim code.

## Current behavior (what we're replacing)

`src/main.cpp:137` calls `wifiManager.connect(config.wifiSsid, …)`. On first
boot `config.wifiSsid` is empty (`ConfigStore::load`, `ConfigStore.cpp:29`), so
`WifiManager::connect` logs *"WiFi SSID is not configured"* and returns false
(`WifiManager.cpp:9`); `setup()` just logs *"WiFi not connected"* and the device
loops forever doing nothing. There is no way in.

## Target flow

```
first boot / no WiFi creds
        │
        ▼
 enter Provisioning mode ──► Improv Serial listens on USB (browser flasher)
        │                    SoftAP "JKBMSR-Setup-XXXX" + captive portal (fallback)
        ▼
 user submits SSID + password
        │
        ▼
 verify: WiFi.begin() succeeds within timeout ──(fail)──► report error, stay in provisioning
        │ (success)
        ▼
 persist creds to NVS (ConfigStore.save)
        │
        ▼
 Improv returns redirect URL to the browser:
   https://web.jkbmsr.com/onboard?device=<deviceId>&code=<claimCode>
        │
        ▼
 continue normal boot (ensureDeviceAuth → register with claimCode → telemetry)
```

---

## Tasks

| ID | Task | New/changed files | Effort | Depends on |
|---|---|---|---|---|
| P1-0 | Add Improv Serial lib + build wiring | `platformio.ini` | 0.5d | — |
| P1-1 | Config: WiFi-configured helper + claim-code field | `ConfigStore.{h,cpp}` | 0.5d | — |
| P1-2 | `ProvisioningManager` (Improv Serial state machine) | `src/provisioning/ProvisioningManager.{h,cpp}` | 3d | P1-0, P1-1 |
| P1-3 | Claim-code generation + Improv success redirect URL | `DeviceIdentity.*`, `ProvisioningManager.*`, `DeviceRegistrationClient.*` | 1.5d | P1-1, P1-2 |
| P1-4 | `main.cpp` integration (setup restructure + runtime fallback) | `src/main.cpp` | 1d | P1-2, P1-3 |
| P1-5 | Re-provision trigger (BOOT long-press / factory reset) | `src/provisioning/ResetTrigger.{h,cpp}`, `main.cpp` | 1d | P1-4 |
| P1-6 | SoftAP captive-portal fallback | `src/provisioning/CaptivePortal.{h,cpp}` | 3d | P1-2, P1-4 |
| P1-7 | Native unit tests | `test/test_provisioning/*` | 1.5d | P1-2, P1-3 |
| P1-8 | **Cross-repo (jkbmsr-api):** accept + enforce claim code | `routes/device.ts`, migration | 1.5d | P1-3 |

Critical path to a demoable "flash → provision over USB → online": **P1-0 → P1-1 → P1-2 → P1-3 → P1-4** (~6.5d). P1-6 (SoftAP) and P1-5 (reset) are parallelizable; P1-8 can proceed in parallel once the claim-code format (P1-3) is fixed.

---

### P1-0 — Improv Serial library + build wiring
- Add to `platformio.ini` `lib_deps`: `jnthas/Improv-WiFi-Library` (Serial
  transport; header-light, no BLE). Pin the version.
- No partition-table change (that's the BLE-deferral payoff). Confirm image
  still fits (~77% flash today).
- **Accept:** clean build for `env:dev`; no new partition CSV required.

### P1-1 — Config: WiFi-configured helper + claim-code field
- `DeviceConfig` (`ConfigStore.h`): add `String claimCode;`.
- Add `inline bool wifiConfigured() const { return wifiSsid.length() > 0; }`
  to `DeviceConfig` so call sites stop hand-checking `wifiSsid.length()`.
- `ConfigStore.cpp`: persist/load NVS key `"claim_code"` alongside the others.
- **Accept:** round-trip save/load of `claimCode`; `wifiConfigured()` false on
  a fresh config, true after creds set.

### P1-2 — ProvisioningManager (Improv Serial state machine)
New module `src/provisioning/ProvisioningManager.{h,cpp}`.
- API sketch:
  ```cpp
  enum class ProvState { Ready, Provisioning, Provisioned, Error };
  class ProvisioningManager {
   public:
    void begin(Stream& io, const String& deviceFirmwareName, const String& deviceId);
    // Pumps Improv packets. Returns true once creds are captured+verified.
    // Fills outSsid/outPass. Non-blocking; call in a loop.
    bool poll(WifiManager& wifi, String& outSsid, String& outPass);
    ProvState state() const;
   private:
    // Improv requires: report current state, answer WIFI_SETTINGS RPC,
    // return device info (firmware name/version, device id), and on success
    // return one or more URLs to the browser.
  };
  ```
- Implements the Improv Serial protocol via the library: respond to
  `GET_CURRENT_STATE`, `GET_DEVICE_INFO`, and `WIFI_SETTINGS` (SSID+pass).
- On `WIFI_SETTINGS`: call `WifiManager::connect(ssid, pass, kWifiConnectTimeoutMs)`.
  Report `Provisioning` while trying; `Provisioned` + redirect URL on success;
  `Error` (with an Improv error code) on failure so the browser shows a retry.
- Keep the existing `Serial` debug logging from stepping on the Improv byte
  stream — either move logs to `Serial` while Improv owns a separate UART, or
  gate `DebugLog` off while `state()==Provisioning`. **Resolve this explicitly;
  it's the classic Improv-Serial footgun.**
- **Accept:** with a fake `Stream`, a scripted `WIFI_SETTINGS` packet drives
  `Ready → Provisioning → Provisioned` and yields the submitted SSID/pass.

### P1-3 — Claim code + Improv redirect URL (closes remaining half of C2)
- `DeviceIdentity`: add `String generateClaimCode() const;` — short,
  human-typeable, high-entropy (e.g. 8 chars base32 from `esp_random`,
  ambiguity-free alphabet). Generated once on first boot next to the device ID
  (`main.cpp:112` block), persisted via `claimCode` (P1-1).
- `DeviceRegistrationClient::registerDevice`: send the claim code so the
  backend binds it to the device row at registration (see P1-8).
- On successful provisioning, `ProvisioningManager` returns the Improv redirect
  URL: `https://web.jkbmsr.com/onboard?device=<deviceId>&code=<claimCode>` so
  the browser deep-links the user straight into claiming — they never type the
  code by hand in the happy path (it's still printed to `Serial` and on the
  physical label for the SoftAP/manual path).
- **Security intent:** claiming a device requires the code, which only someone
  with physical access (or who ran the flasher) has — this is the anti-spoof
  half of C2. The code is a *claim* secret, not the device auth secret.
- **Accept:** claim code is stable across reboots, unique per device, present
  in the register request and the redirect URL.

### P1-4 — main.cpp integration
- In `setup()` after config load / ID+floor init:
  ```cpp
  if (!config.wifiConfigured() || resetTrigger.provisioningRequested()) {
    runProvisioning();   // Improv Serial (+ SoftAP once P1-6 lands), save creds
  }
  wifiManager.connect(config.wifiSsid, config.wifiPassword, kWifiConnectTimeoutMs);
  ```
- `runProvisioning()`: pump `ProvisioningManager::poll(...)` (and CaptivePortal
  once P1-6 is in) until creds captured or a bounded timeout; on capture,
  `configStore.save(config)`.
- **Runtime fallback:** if WiFi is down for a sustained window in `loop()`
  (e.g. N consecutive failed reconnects), re-enter provisioning rather than
  looping dead — so a moved/renamed router is recoverable without a reflash.
- Keep telemetry/OTA/config-fetch loop untouched.
- **Accept:** on a wiped NVS the device enters provisioning; after a browser
  submits creds it connects and proceeds to `ensureDeviceAuth()` normally.

### P1-5 — Re-provision trigger
New `src/provisioning/ResetTrigger.{h,cpp}`.
- Hold BOOT (GPIO0) for ~5s → `provisioningRequested()` true (soft: keep device
  ID / floor / claim code, clear only WiFi creds + JWT).
- Optional longer hold (~10s) → full factory reset (also clears device secret;
  forces re-registration).
- Debounce; sample early in `setup()` and also watch during `loop()`.
- **Accept:** short hold clears WiFi + JWT only and re-enters provisioning;
  device ID/claim code survive.

### P1-6 — SoftAP captive-portal fallback
New `src/provisioning/CaptivePortal.{h,cpp}`.
- Raise AP `JKBMSR-Setup-XXXX` (XXXX = last 4 of device ID), **WPA2** with a
  per-device password **derived from the claim code** — not an open AP and not
  a shared published constant. The SSID suffix is public, so a published
  password would let anyone nearby join the setup network; the claim code stays
  a separate per-device secret used only for account onboarding, but it is also
  what the AP password is derived from, so possession of the claim code is now
  required to reach the portal at all.
  *(Originally specified here as a shared documented password `…`. Changed
  2026-09-26: that value was published in docs, printed to serial, and left
  the claim code readable by any client that joined the AP.)*
- The portal additionally mints a per-session token embedded in the setup form
  and required on `POST /save`, so a client that reaches the server by any
  other route cannot submit credentials and repoint the gateway.
- `DNSServer` (wildcard → self) + `WebServer`: serve a self-contained page
  (scan SSIDs, enter password), POST creds; verify via `WifiManager::connect`;
  on success save + show the same onboard URL as Improv.
- Feeds the same `runProvisioning()` capture path as P1-2.
- **Accept:** phone joins AP, submits creds, device connects; wrong password
  re-prompts without crashing the portal.

### P1-7 — Native unit tests (`test/test_provisioning/`)
Matches the existing native/`test_build_src` setup.
- `ProvisioningManager` state machine over a fake `Stream` (P1-2 accept case
  + error/retry path).
- Claim-code generator: length, alphabet, non-repeating across calls.
- `DeviceConfig::wifiConfigured()` / `ConfigStore` claim-code round-trip.
- Redirect-URL builder emits the exact `onboard?device=…&code=…` string.
- **Accept:** all green in the native env alongside the current suite.

### P1-8 — Cross-repo backend (jkbmsr-api)
Not firmware, but P1-3 is inert without it. Track under the cloud repo:
- Migration: add `claim_code` (hashed) to `devices`; store at registration.
- `POST /register` (device): accept + persist the claim code.
- Device-claim endpoint: **require** a matching claim code before binding a
  device to a user account (this is the actual C2 enforcement).
- `/onboard` route in `jkbmsr-web`: read `device` + `code` from the query and
  prefill the claim form.
- **Accept:** claiming without/with a wrong code is rejected; correct code
  binds the device.

---

## Out of scope for Phase 1 (later)
- Improv-over-BLE (cable-free setup) — needs BLE stack + partition-table work.
- Flash/NVS encryption + Secure Boot v2 (H6, Phase 2) — the creds this phase
  writes to NVS are still plaintext until then; that's expected and sequenced.
- In-app (Flutter) provisioning — once `jkbmsr-pro` exists.
