# Hardware Security Hardening Plan (H6 + H7)

Draft for the hardware / firmware decision on the two remaining audit items
that need a hardware-lifecycle choice rather than just code:

- **H6 — Secrets at rest are plaintext.** WiFi SSID/password, the device
  secret, and the JWT live in NVS via `Preferences`, unencrypted. Physical
  access (JTAG, UART bootloader, an `esptool.py` flash dump) recovers them in
  plaintext. Realistic for RV / shed / off-grid / shared-site placements.
- **H7 — No WiFi provisioning.** There is no way for a non-technical user to
  get WiFi credentials onto a device; today they must be pre-loaded per unit.
  This blocks the "plug-and-play, no VPN/port-forwarding, easy for
  non-technical users" product promise, and is itself a security question
  (how are credentials transmitted?).

These are coupled: the provisioning flow (H7) is *where* per-device secrets and
WiFi credentials are first written, and encryption-at-rest (H6) is what
protects them afterward. They also share one upstream decision — the build
system — so decide them together.

---

## The upstream decision: Arduino + PlatformIO vs. ESP-IDF

Both items are materially easier on **ESP-IDF** than on Arduino-via-PlatformIO:

- Flash encryption, NVS encryption, and Secure Boot v2 are first-class,
  well-documented sdkconfig options in ESP-IDF. On plain Arduino/PlatformIO
  they require hand-managed partition tables, `sdkconfig` overrides, and build
  flags — possible, but fiddly and easy to get subtly wrong (a security-
  sensitive place to be fiddly).
- BLE / unified WiFi provisioning ships as IDF components (`wifi_provisioning`)
  with official iOS/Android apps. Arduino has thinner wrappers (`WiFiProv`).

**Options**

| Option | Effort | Notes |
|---|---|---|
| Stay Arduino + PlatformIO, configure the hard bits via flags/partitions | Low-med | Keeps everything as-is; most friction and footguns on the security config |
| **Arduino as an ESP-IDF component** (recommended) | Medium | Keep the existing Arduino code (`Serial2`, `WiFi`, `HTTPClient`, `Preferences`, `Update`) largely intact, but gain full IDF config for encryption/secure-boot/provisioning |
| Full rewrite to ESP-IDF | High | Most control, biggest change; not justified for v1 |

**Recommendation:** migrate to **Arduino-as-ESP-IDF-component** when tackling
H6/H7. It preserves the current firmware logic while unlocking the security and
provisioning features cleanly. This is the single biggest decision here.

---

## H7 — WiFi provisioning (do this first)

Highest product value: it unblocks non-technical onboarding, and it is
lower-risk than H6 (no irreversible eFuse burning).

### Transport options

| Approach | UX | Needs an app? | Fit |
|---|---|---|---|
| **Improv Wi-Fi over BLE** (recommended) | Flash + provision in one browser flow | No — Chrome/Edge Web Bluetooth | **Integrates with the web flasher already at `cdn.jkbmsr.com/flash`** |
| SoftAP captive portal | Join a `JKBMSR-Setup` Wi-Fi, fill a form | No | Good field re-provisioning fallback |
| ESP unified provisioning (SoftAP/BLE) | Espressif's official phone apps | Yes (or Web Bluetooth) | Batteries-included but app-dependent |
| In the planned Flutter app | In-app setup | Yes (jkbmsr-pro, not built yet) | Later, once the app exists |

**Recommendation:** **Improv Wi-Fi as the primary path**, because ESP Web Tools
(the browser flasher we already ship) has built-in Improv support — the same
Chrome page that flashes the device can immediately prompt for the home Wi-Fi
and send it to the device. One flow: *plug in → flash → enter Wi-Fi → done*, no
app, no network switching. Add a **SoftAP captive portal as a fallback** for
re-provisioning a device already in the field (hold a button to enter setup
mode) where a USB cable isn't handy.

> **Transport note (Phase 1):** ESP Web Tools performs the post-flash handoff
> over **Improv *Serial*** (the same USB/Web-Serial connection used to flash),
> not BLE. Serial is the Phase-1 transport: no BLE stack, no partition-table
> change, smaller image. **Improv-over-BLE is deferred** to a later phase for
> cable-free setup once the BLE flash-footprint/partition work is scoped.
> See `docs/phase1-provisioning-spec.md` for the task breakdown.

### Security of the provisioning channel

- Provisioning must not send Wi-Fi credentials in the clear. Improv and ESP
  unified provisioning both support a **proof-of-possession (PoP) code** +
  session encryption — require it. The PoP can double as the anti-spoofing
  **per-device claim secret** that closes the remaining half of C2 (device
  identity): burn/print a unique code per unit; the device won't accept
  provisioning or first-registration without it.
- A SoftAP fallback should use WPA2 (not an open AP) with a per-device
  password, or keep the setup window short and encrypt the credential POST.

### Firmware work

- Replace the "credentials must already be in NVS" assumption in `main.cpp` /
  `WifiManager` with: if no stored Wi-Fi, enter provisioning mode
  (BLE-advertise for Improv; optionally raise SoftAP) instead of idling.
- Persist provisioned credentials (and the claim secret) to NVS — which is
  exactly what H6 then protects.
- Add a "reset to provisioning" trigger (long button press / factory reset).

---

## H6 — Encrypt secrets at rest (before commercial production)

### What's actually required on ESP32

Encrypting NVS needs **two** things, not one:

1. **Flash Encryption** — encrypts app, bootloader, and (with the key
   partition) protects the NVS-encryption keys. Note: flash encryption **does
   not** encrypt NVS data by itself.
2. **NVS Encryption** — encrypts the NVS partition contents using keys stored
   in a dedicated `nvs_keys` partition, which is in turn protected by flash
   encryption.

Strongly pair both with **Secure Boot v2** (only firmware signed by your key
runs), so an attacker can't flash a malicious image to read secrets out or
disable checks.

### The irreversible part (why this is a hardware decision)

Flash encryption has **Development** and **Release** modes:

- **Development mode** — lets you re-flash plaintext images over USB during
  bring-up. Use this on dev boards.
- **Release mode** — burns one-time-programmable **eFuses** that disable UART
  download and JTAG and lock the key as unreadable. **This is irreversible and
  per-device**, done on the manufacturing line. Get it wrong and the unit is
  bricked; after it, updates come only via signed OTA (which we already have,
  with anti-rollback).

### Key-provisioning choice

- **Device-generated keys** (recommended) — the ESP32 generates its encryption
  key on first secure boot; the key never leaves the chip. Most secure; each
  unit is unique; you cannot re-flash an encrypted image from the host.
- **Host-generated keys** — you generate/burn keys, enabling host re-flashing
  of encrypted images. Needed only if the manufacturing flow requires
  re-flashing encrypted binaries; larger key-management burden.

### Compatibility

Existing already-flashed units cannot be encrypted retroactively without a
physical re-flash + eFuse burn. This is a **new-hardware-revision / production-
run** change, not an OTA.

---

## Decisions needed from you

1. **Build system:** move to Arduino-as-ESP-IDF-component? (Recommended: yes.)
2. **Provisioning transport:** Improv-over-BLE primary + SoftAP fallback?
   (Recommended.) Or app-based / SoftAP-only?
3. **Proof-of-possession code:** adopt a per-device provisioning/claim secret
   (also finishes C2)? (Recommended: yes.)
4. **Flash encryption timing:** dev-mode now on prototypes; release-mode +
   Secure Boot v2 gated to the first commercial production run? (Recommended.)
5. **Key provisioning:** device-generated keys? (Recommended, unless the
   factory flow needs host re-flash.)
6. **Manufacturing:** who runs the eFuse-burn + claim-code step, and is there a
   line procedure + QA for it? (New process to define.)

---

## Suggested sequencing

- **Phase 1 — Provisioning (H7).** ✅ Done. Improv *Serial* (USB) primary +
  SoftAP captive-portal fallback, claim-code PoP, NVS persistence, BOOT
  long-press reset. Spec: `docs/phase1-provisioning-spec.md`.
- **Phase 2 — Encryption at rest (H6), dev mode.** In progress / mostly
  software-complete: Arduino-as-IDF (`env:idf`), flash+NVS encryption
  (`env:idf-secure`), Secure Boot v2 signed images (`env:idf-secureboot`,
  ECO3+). Spec: `docs/phase2-encryption-spec.md`. Bring-up:
  `docs/secure-bringup.md`. **Remaining:** hardware checklist (P2-5) before
  flipping the default/release build off `env:dev`.
- **Phase 3 — Production hardening.** Release-mode eFuse burn + key/claim
  provisioning on the manufacturing line, with a written, tested procedure and
  QA. Gate to the first hardware production run. *Process + validation, timed
  to manufacturing.*

## Risks / watch-items

- Release-mode flash encryption is **irreversible** — validate the entire
  dev-mode flow (including OTA under encryption) before ever burning release
  eFuses; brick a few dev units on purpose to prove the recovery story.
- Confirm **OTA under flash encryption** end-to-end early — the `Update`
  path must write correctly-encrypted images (it does when configured right,
  but verify on real hardware).
- BLE increases firmware flash footprint; check it fits the partition scheme
  (currently ~77% flash used) — may need a partition-table revisit.
- Keep the OTA signing key and any secure-boot signing key in separate,
  escrowed key management (see `.env.example` and the OTA signing docs).
