# ESP32-S3-N16R8 under arduino-esp32 3.x / ESP-IDF 5.x

Status: **adopted as the `env:esp32-s3-16mb` build; not hardware-validated.** No
release was cut from this change. The owner approves any release and any
flash-to-hardware test.

## Why

The ESP32-S3-N16R8 module (16 MB flash, 8 MB Octal PSRAM) fails to boot on the
current firmware: a clean flash (all parts written OK) then loops forever on

```
invalid header: 0x1246e706
```

The current targets are built with the official PlatformIO `espressif32`
platform 7.0.1, which pins framework-arduinoespressif32 3.20017 (Arduino-ESP32
2.0.17 / **ESP-IDF v4.4.7**). A known-working image for the same module was
built with **arduino-esp32 3.2.0 / ESP-IDF v5.4.1**, and its second-stage
bootloader is **20208 bytes**. Ours is **15104 bytes / v4.4.7**. The leading
hypothesis is a framework-generation difference — most plausibly IDF 4.4's
flash-support code not handling this module's non-standard flash
(`Flash ID: 1820c2`).

This spike tests that hypothesis at the build level: build the **existing,
unmodified firmware source** against the same framework generation as the
working image, and produce flash artifacts a human can put on hardware.

## The platform, and what it provides

The official `platformio/espressif32` is stuck on Arduino-ESP32 2.x. The
community **pioarduino** fork ships 3.x. The release that matches the
known-working colleague stack exactly is:

```
https://github.com/pioarduino/platform-espressif32/releases/download/54.03.20/platform-espressif32.zip
```

Release **`54.03.20`** — *"Arduino Release v3.2.0 based on ESP-IDF v5.4.1"*,
published 2025-03-28. Read from the release's own `platform.json` (not
inferred):

| Package | Version |
| --- | --- |
| `platform` (espressif32) | 54.03.20 (pioarduino) |
| `framework-arduinoespressif32` | **3.2.0** (`esp32-3.2.0.zip`) |
| `framework-arduinoespressif32-libs` | IDF **release_v5.4**, build `2f7dcd86-v1` |
| `framework-espidf` | **v5.4.1** |
| `toolchain-xtensa-esp-elf` | 14.2.0+20241119 |
| `toolchain-riscv32-esp` | 14.2.0+20241119 |
| `tool-esptoolpy` | pioarduino esptool v4.8.9 |

Nearest neighbours, for reference: `54.03.21` and `54.03.21-2` are Arduino
**3.2.1** / IDF **5.4.2**, and `54.03.20` is the exact 3.2.0 / 5.4.1 match. We
pin `54.03.20` deliberately, because that is the stack the working image used.

## The adopted environment

This began as a build-only spike (`env:esp32-s3-16mb-idf5` in a separate
`platformio-idf5.ini`, kept out of the build scripts on purpose). It is now the
**canonical `env:esp32-s3-16mb`** in `platformio.ini`: same env name, same
product target, built against the 3.x framework. The spike's separate file and
its `extra_configs` registration were removed, so there is one env, not two.

The env keeps the exact geometry it had: `board = esp32-s3-devkitc-1`,
`board_upload.flash_size = 16MB`, `board_build.flash_size = 16MB`,
`board_build.arduino.memory_type = qio_opi`, `board_build.flash_mode = qio`, and
`partitions-16mb-ota.csv`. Its `JKBMSR_TARGET_HARDWARE` stays
`"esp32-s3-16mb"` — a device running it still reports a string `jkbmsr-api`'s
catalog already knows. The only env-level change from the old official-platform
build is `platform` (now the 54.03.20 fork URL) and `NimBLE-Arduino` 1.4.3 →
**2.5.1** (the 2.x branch is the one that supports core 3.x; same pin the C6 env
uses).

**Isolation is now automatic, not manual.** With the env back in the main file,
`run-checks.sh` and `release.sh` build it, so the two-pioarduino-release
collision has to be handled there. Both scripts source
`scripts/lib/platform-isolation.sh`, which gives every distinct platform spec
its own PlatformIO core dir:

```
platform = espressif32@7.0.1  (official)  -> .platformio-core/               (shared)
.../releases/download/54.03.20/... (S3)   -> .platformio-core-pioarduino-54.03.20
.../releases/download/55.03.311/...(C6)   -> .platformio-core-pioarduino-55.03.311
```

Before this, both fork releases shared `.platformio-core-pioarduino` and would
have clobbered each other exactly like the official/fork pair.

To build it by hand, either let the default core dir apply or name it yourself:

```bash
cd firmware
pio run -e esp32-s3-16mb
# or, explicitly:
PLATFORMIO_CORE_DIR="$PWD/.platformio-core-pioarduino-54.03.20" \
  pio run -e esp32-s3-16mb
```

## Result — the real firmware compiles

**The existing firmware source compiles and links unchanged under arduino-esp32
3.2.0 / IDF 5.4.1.** No source changes were needed. The codebase already
carries the 3.x compatibility guards added for the C6 target (they key on
`ESP_ARDUINO_VERSION_MAJOR >= 3` and `NIMBLE_CPP_VERSION_MAJOR >= 2`), so
`SecureClient.cpp`'s two-argument `setCACertBundle`, the `NetworkClient` stream
type in `OtaClient.cpp`, and the NimBLE-Arduino 2.x scan-result types are all
already handled. The only env-level change is `NimBLE-Arduino` 1.4.3 → **2.5.1**
(the 2.x branch is the one that supports core 3.x; same pin the C6 env uses).

Build output (recorded while the env was still named `esp32-s3-16mb-idf5`; the
env is now `esp32-s3-16mb` and builds the same way):

```
Environment         Status    Duration
esp32-s3-16mb-idf5  SUCCESS   00:10:08
RAM:   [==        ]  20.4% (used 66704 bytes from 327680)
Flash: [==        ]  19.2% (used 1550086 bytes from 8060928)
```

## Bootloader and image, measured

| Artifact | Previous (`esp32-s3-16mb`, IDF 4.4.7) | Now (`esp32-s3-16mb`, IDF 5.4.1) |
| --- | --- | --- |
| `bootloader.bin` | 15104 B | **20208 B** |
| `partitions.bin` | 3072 B | 3072 B |
| `boot_app0.bin` | 8192 B | 8192 B (byte-identical) |
| `firmware.bin` | 1 309 216 B | 1 550 480 B |

**The new bootloader is 20208 bytes — exactly the size of the colleague's
working bootloader** — and it directly carries the version string
`v5.4.1-1-g2f7dcd862a-dirty` in its own rodata (found with `strings`). The
compiled image's `esp_app_desc.idf_ver` reads the same. The previous image's
`esp_app_desc.idf_ver` reads `v4.4.7-dirty`. (Second-stage bootloaders in IDF
4.4 did not embed a version string; the IDF 5.x one does, which is why the new
one is directly self-identifying.)

Both bootloaders carry flash mode **DIO**, 80 MHz, flash-size code `0xf`
(16 MB), and the generated partition table is byte-for-byte the intended
`partitions-16mb-ota.csv`:

```
nvs       0x9000    20K
otadata   0xe000     8K
app0      0x10000  7872K
app1      0x7c0000 7872K
spiffs    0xf70000  512K
coredump  0xff0000   64K
```

`nvs 0x9000 / otadata 0xe000 / app0 0x10000` are unchanged, so the browser
flasher's fixed offsets still apply.

## Flash artifacts

Staged (untracked, alongside the build they came from) at:

```
firmware/.pio/idf5-flash/
```

Contents and SHA-256:

```
12c9a10fef2d95a3f6d74dc6089fa8fedc51a77a487be834c9207b8c687b8761  bootloader.bin   (20208 B)
22ccfef9647bbe2049a8d5ea8a0a5824bd60803c47e71d7f77092ca3bb2e09d0  partitions.bin   (3072 B)
f94c5d786a7a8fab06ac5d10e33bf37711a6697636dc037559ea19cc410a17f0  boot_app0.bin    (8192 B)
03b1f3bbd57e2323869b8c3a25cd465c3ccb9665f5feadb5fc258ffd4c166b9c  firmware.bin     (1550480 B)
```

`flash-manifest.json` (generated by `scripts/generate-flash-manifest.py`
against the `esp32-s3-16mb` catalog entry, version `0.9.4-idf5spike`) declares
the same four parts at offsets 0x0 / 0x8000 / 0xe000 / 0x10000.

Flashing is a normal full write of the four files at those offsets — e.g. the
ESP Web Tools flow (`flash-manifest.json` + the four `.bin`s side by side), or:

```
esptool.py --chip esp32s3 write_flash \
  0x0     bootloader.bin \
  0x8000  partitions.bin \
  0xe000  boot_app0.bin \
  0x10000 firmware.bin
```

## What this does NOT establish

- **It does not prove the module boots.** There is no hardware here. The build
  evidence (bootloader size and IDF version matching the working image) is
  consistent with the hypothesis but is not a boot.
- **The non-standard flash (`Flash ID: 1820c2`) is not exercised by a build.**
  Whether IDF 5.4.1's flash support handles it is exactly what a flash-and-boot
  test has to answer; nothing here does.
- **No runtime behaviour is validated** — WiFi, BLE, TLS, OTA, PSRAM. Only
  compilation and image layout were measured.
- **`run-checks.sh` and `release.sh` build it, but nothing here ran the full
  matrix to green.** The env is in `run-checks.sh`'s `BUILD_MATRIX` (it always
  was, under this name) and in `release.sh`'s `RELEASE_MATRIX`, so it is a real
  target now rather than a side file; verifying a full green matrix run and a
  real release is the owner's call.

## Next step

Flash the built artifacts to the N16R8 and confirm the boot banner. If it boots,
the framework generation is confirmed as the fix; if it still fails, the flash
chip itself (`1820c2`) is the next thing to isolate. Either way a release needs
the owner.
