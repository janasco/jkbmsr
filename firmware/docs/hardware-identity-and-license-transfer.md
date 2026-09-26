# Hardware identity and transferable licenses

JKBMSR keeps three concepts separate:

1. **Hardware fingerprint** — a stable, platform-namespaced factory UID used
   only to recognize the same physical controller after a full storage erase.
   The API HMACs it before database storage. It is never an authentication
   secret.
2. **Logical gateway identity and secret** — a random device ID plus rotating
   secret stored in protected configuration. These authenticate cloud traffic
   and survive ordinary firmware updates and factory-setting resets.
3. **License entitlement** — owned by the user's account and optionally
   assigned to one gateway. Deleting a broken gateway releases the entitlement
   instead of deleting the purchase.

## Platform adapters

Each supported controller must provide a lowercase platform key, a model, and
a namespaced fingerprint value:

- ESP32: `esp32` + `efuse-v1:<12-hex eFuse MAC>`
- ESP8266: `esp8266` + `chipid-v1:<factory chip id>`
- STM32: `stm32` + `uid-v1:<96-bit factory UID>`

Future platforms must use their factory-programmed unique ID where available.
If a controller has no stable factory UID, it must use a provisioned random
hardware secret in protected storage and cannot promise continuity after a
complete storage erase.

## Recovery behavior

Normal web flashing does not erase the configuration partition, so the random
logical ID and secret remain unchanged. After a complete NVS erase, firmware
mints fresh credentials but reports the same hardware fingerprint. When the
signed-in owner proves possession with the new claim code, the API moves the
old gateway's name, history, settings, shares, subscription, and assigned
license to the fresh credential record and removes the stale duplicate.

A matching UID owned by another account is never sufficient to claim or merge
a gateway. The prior owner must remove the old gateway or transfer its license;
the UID remains a lookup key, not a password.

The device secret is also used at every boot and periodically while online to
renew short-lived API tokens. A continuously powered gateway therefore does
not stop uploading when an individual API token expires.
