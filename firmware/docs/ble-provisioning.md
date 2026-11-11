# BLE provisioning protocol

Status: **specification, agreed 2026-11-11.** Implementation follows in the
firmware, then the JK BMS Remote app. Nothing here is live.

## Decisions it encodes

| | decision | why |
|---|---|---|
| D1 | **Setup code from the serial log** | the payload carries a WiFi password and a claim token; the code is physical-presence proof, and the person flashing already has the console open |
| D2 | **SoftAP and Improv are removed in the same release** | owner's call: one path. Recovery from a failed setup is a USB reflash, and the claim token reaches the device only over BLE |
| D3 | **The service is visible only while the gateway cannot reach the network** | a running gateway must not be provisionable by anyone in range, and advertising costs radio time that belongs to the pack link |

### When the service is visible

This was first specified as *always advertised*, on the reasoning that a gateway
should be reconfigurable without touching it. That was wrong, and the correction
is now the rule:

```
never configured          -> advertise
configured, WiFi connected -> do not advertise
configured, WiFi down      -> advertise, but only after 60 s down
```

Two reasons, both concrete. A running gateway that advertises can be claimed by
anyone within radio range who can also read the setup code, and the pack link is
the most timing-sensitive path in the product - 0.9.12 drops a link that goes
silent for 30 s, and radio starvation looks identical. Restricting the service to
"cannot reach the network" removes both problems: provisioning and the pack link
are never live at the same time, so there is no contention to measure.

**The 60 s grace is security, not politeness.** Jamming 2.4 GHz is easy; without
it, an attacker could force the WiFi down, wait for the window, and provision the
device. Sixty seconds is longer than the first reconnect attempts, so an ordinary
blip recovers without ever advertising, and a deliberate, sustained outage is the
only thing that opens the window.

Consequence for the firmware's WiFi failure loop: it currently restarts the
gateway on repeated failure. It must instead enter provisioning after the grace
period, because restarting forever never offers the owner a way to fix a wrong
password.

## Service## Service

| | UUID |
|---|---|
| service | `9a1f0000-7c3b-4d2e-9f10-6b5a8e2c4d70` |
| `status` | `9a1f0001-...` read, notify |
| `setup` | `9a1f0002-...` write |
| `payload` | `9a1f0003-...` write without response |
| `command` | `9a1f0004-...` write |

Advertised name: `JKBMSR-Setup-XXXX`, where XXXX is the last two bytes of the
device id (the same suffix the SoftAP used, so the muscle memory survives).

## Authentication (D1)

The device generates six digits and prints them:

```
[info] Setup code: 418302
```

That line is already visible in the flasher's console.

**The code is stable while the device is unprovisioned**, stored in NVS, and
regenerated only by a factory reset. The first draft had it regenerated on every
boot, and that breaks the actual flow: flashing happens over USB, the device is
then moved to the pack, and moving it reboots it - so a per-boot code would be
dead before the owner reached the app. Stability also lets a future flasher hand
the code to the app through the API instead of the owner typing it.

**It is never readable over BLE.** The characteristic is write-only and the
device only answers accepted or rejected; a code the app could read would prove
nothing, because anyone in range could read it too. It is out-of-band proof, and
the out-of-band channel is the console the owner already has open.

Brute force is closed by the lockout: three wrong codes drop the connection, and
successive lockouts back off (5 s, 30 s, 5 min), so a million candidates is not
reachable in the minutes a device sits unprovisioned and powered.

- The app writes the six ASCII digits to `setup`.
- Three wrong codes drop the connection and require a scan again.
- No credential write is accepted before `setup` succeeds; the status
  characteristic answers `locked` until then.

## Payload transport

The claim token is a JWT and cannot fit one ATT write, so `payload` is a
**chunked buffer**:

```
byte 0-1  offset, little endian, in bytes
byte 2..  data
```

The app writes chunks in any order (offset-addressed), then writes `commit` to
`command`. The firmware requires:

- total length 1..768 bytes (WiFi credentials, zone and token together);
- no gaps and no overlap;
- the assembled bytes parse as JSON (see below);
- `commit` within **60 s** of the first chunk, otherwise the buffer is cleared
  and the status returns `idle`.

## Payload shape

```json
{
  "ssid": "string, 1..32 bytes",
  "password": "string, 0..63 bytes (0 = open network)",
  "timeZone": "POSIX TZ string, e.g. PST-8 (validated as today)",
  "claimToken": "string, the JWT from POST /devices/claim-token"
}
```

Every field is validated with the same rules the HTTP paths use. A rejected field
returns `invalid:<field>` and the buffer is **not** applied - a half-written
configuration is worse than none.

## State machine

```
advertising
  -> connected          (one connection only)
  -> authenticated      (setup code accepted; 60 s to commit)
  -> applying           (payload committed and validated)
  -> rebooting          (stored; device restarts into station mode)
  -> registering        (POST /device/register with the claim token)
  -> running            (claim bound; BLE central link to the BMS starts)

any state -> advertising  on disconnect, timeout, or failure
```

`status` notifies a single UTF-8 string: one of the states above, or
`failed:<reason>` with `reason` in `{code, payload, json, ssid, timezone,
token, storage}`.

## What is deliberately absent

- **No WiFi scan over BLE.** The app sends a network the phone already knows; a
  scan would add a second radio-heavy flow and a long list over a slow link.
  Adding it later is additive, not a redesign.
- **No firmware update over BLE.** OTA stays as it is.
- **No BLE pairing/bonding.** The setup code is the authentication (D1); a bonded
  link adds Android pairing UI and a second failure mode for no gain while the
  code is per-boot.

## Testable core

Three pure pieces, all host-testable, and they are where the mistakes would be:

1. **Chunk assembler**: offsets, gaps, overlap, overflow, commit, timeout reset.
2. **Payload validation**: every field rule, and the all-or-nothing behaviour.
3. **State machine**: transitions, three-strike auth, idle timeout, and the
   guarantee that no credential write is accepted before authentication.

The radio itself is not host-testable; it is verified on hardware, including the
D3 measurement above.
