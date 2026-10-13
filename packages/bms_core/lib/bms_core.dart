/// Pure-Dart JK-BMS protocol, telemetry model, and device-detection core.
///
/// This library is platform-agnostic: it has no Flutter dependency and can
/// run on the Dart VM, in tests, or inside a Flutter app. Import it as a
/// single barrel:
///
/// ```dart
/// import 'package:bms_core/bms_core.dart';
/// ```
library;

export 'src/detection/brand_registry.dart';
export 'src/detection/detection_engine.dart';
export 'src/models/bms_models.dart';
export 'src/models/bms_parameter.dart';
export 'src/protocols/bms_protocol.dart';
