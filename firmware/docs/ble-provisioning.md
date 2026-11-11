# BLE provisioning protocol

Status: **specification, agreed 2026-11-11.** Implementation follows in the
firmware, then the JK BMS Remote app. Nothing here is live.

## Decisions it encodes

| | decision | why |
|---|---|---|
| D1 | **Setup code from the serial log** | the payload carries a WiFi password and a claim token; the code is physical-presence proof, and the person flashing already has the console open |
| D2 | **SoftAP and Improv are removed in the same release** | owner's call: one path. Recovery from a failed setup is a USB reflash, and the claim token reaches the device only over BLE |
| D3 | **The provisioning service is always advertised** | owner's call: a gateway can be reconfigured at any time without touching it |

### What D3 costs, and how it is bounded

The ESP32-S3 has **one radio** and it is already a BLE **central** to the JK-BMS.
Advertising alongside a connection is cheap (three packets per advertising
interval); **a second connection** is what competes with the BMS link for
connection events, and the BMS stream is our most timing-sensitive path - the
gateway drops a link that goes silent for 30 s (0.9.12), and radio starvation
looks exactly like that.

So "always advertised" is honoured, with three hard bounds:

1. **One provisioning connection at a time.** A second phone is refused while the
   first is connected.
2. **An idle connection is dropped after 60 s**, and a connection that fails
   authentication is dropped immediately.
3. **The provisioning connection uses a slow interval** (requested 100 ms) so it
   cannot monopolise the radio.

**This must be measured on hardware with a pack connected**, not assumed: a
gateway with a phone attached must keep decoding frames with no gap near 5 s. If
it does not, the fallback is to stop advertising while the BMS link is up, and
that is a conversation, not a silent change.

## Service

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

The device generates six digits at boot and prints them:

```
[info] Setup code: 418302
```

That line is already visible in the flasher's console. It is regenerated on every
boot, so a code photographed last month is useless.

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
