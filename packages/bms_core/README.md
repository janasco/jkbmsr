# bms_core

Pure-Dart core for talking to a JK-BMS over Bluetooth Low Energy: the JK02
frame codec, the decoded telemetry and settings models, and brand
detection. No Flutter, no platform channels — it runs on the Dart VM and in
tests, and any Flutter app can depend on it.

## What's in it

- **`BmsProtocolHelper`** (`lib/src/protocols/bms_protocol.dart`) — JK02 frame
  build/parse (`parseJk02CellInfoFrame`, `parseJk02DeviceInfoFrame`,
  `parseJk02SettingsFrame`, `parseJk02LogbookFrame`), GATT service/characteristic
  UUIDs, brand request frames, logbook event codes, and the CRC routines.
- **Models** (`lib/src/models/`) — `BmsStatus`, `CellInfo`, `BmsAlarms`,
  `BmsBrand`, `BmsCapabilities`, `BmsModelInfo`, `BmsSettingsSnapshot`,
  `BmsParameter` and the per-brand `BmsParameterSchema`.
- **Detection** (`lib/src/detection/`) — `DetectionEngine`, which ranks the
  plausible brand(s) for a scanned device from its advertised name and GATT
  service UUIDs, and `BrandRegistry`/`BrandSignature`, the detection
  signatures it ranks against.

Everything is exported from the single barrel `package:bms_core/bms_core.dart`.

## Usage

```dart
import 'package:bms_core/bms_core.dart';

final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(frame);
final best = DetectionEngine.bestFor(name: device.name, serviceUuids: device.uuids);
```

This package owns the protocol only. The BLE transport (scanning, connecting,
notification reassembly) and all UI live in the applications that depend on it.

## Tests

```
dart pub get
dart test
```

The suite covers the decoder boundaries against real captured JK02 frames,
brand detection and service-UUID ranking, and the parameter schema.

## Scope

JK-BMS is the only publicly supported brand. The other decoders are retained
internally because detection ranking depends on the full multi-brand service
UUID map (0xFFE0 and 0xFF00 are each shared by several protocols), not because
they are a support claim. `BmsBrand.isPublic` gates presentation, never
detection.
