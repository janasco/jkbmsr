# Firmware Downloads

JK BMS Remote firmware is installed **from the logged-in browser flasher**:

- <https://web.jkbmsr.com/flash>

An account is required. Firmware is delivered only through the authenticated
JK BMS Remote API (`api.jkbmsr.com`), which streams the release to a signed-in
browser. There is **no public, anonymous firmware download**. `cdn.jkbmsr.com`
no longer serves firmware binaries or a `firmware/` index.

## Installing firmware

1. Sign in at <https://web.jkbmsr.com>.
2. Open the flasher at <https://web.jkbmsr.com/flash> (Chrome or Edge, desktop).
3. Connect the gateway over a USB **data** cable and click **Connect and
   install**.
4. Complete Wi‑Fi provisioning (Improv Serial) when prompted, then claim the
   device.

See [Firmware Flashing](/getting-started/firmware-flashing) for the full path.

## Why an account

Firmware delivery is gated to keep anonymous bulk downloads, hotlinks and
link-shared copies out of circulation. A logged-in user can still save the
bytes the browser writes — the gate stops anonymous distribution, it is not
device binding.

## Public verification material

The signed OTA metadata and the OTA public key remain public so a customer or
device can verify a release independently:

- `https://cdn.jkbmsr.com/ota/<target>-latest.json`
- `https://cdn.jkbmsr.com/ota/keys/public/<key-id>.pem`
- `https://cdn.jkbmsr.com/docs/VERIFY_FIRMWARE.md`

Release notes and checksums are shown in the flasher for the release it is
about to install.

JK BMS Remote version 1 supports JK-BMS only.
