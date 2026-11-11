import '../../models/device.dart';
import '../../models/telemetry.dart';
import 'pack_check.dart';

/// Builds the pack-check input from what the API returned.
///
/// Extracted so every surface that asks "is this pack healthy" builds the input
/// the same way. Two builders is two chances to disagree about what "no data"
/// means, and a safety screen that disagrees with the dashboard teaches people
/// to ignore both.
PackCheckInput packCheckInputFor(Device device, Telemetry telemetry) {
  // Same no-data signal the dashboard uses: the API sends voltage/SOC as 0
  // when no telemetry row exists, and a real connected pack never sits at
  // exactly 0 V.
  final hasTelemetry = telemetry.voltage > 0.5 || telemetry.soc > 0;
  final link = telemetry.linkDiagnostics;

  return PackCheckInput(
    deviceName: device.name,
    hasTelemetry: hasTelemetry,
    cellVoltages:
        hasTelemetry ? [for (final cell in telemetry.cells) cell.voltage] : const [],
    temperature1C: telemetry.temperature1,
    temperature2C: telemetry.temperature2,
    socPercent: hasTelemetry ? telemetry.soc : null,
    currentAmps: hasTelemetry ? telemetry.current : null,
    fullCapacityAh:
        telemetry.bms.fullCapacityAh > 0 ? telemetry.bms.fullCapacityAh : null,
    isCharging: telemetry.bms.charging,
    isDischarging: telemetry.bms.discharging,
    bmsLinkUp: link.bmsLinkUp,
    secondsSinceLastTelemetry: device.secondsSinceLastTelemetry,
    expectedIntervalSeconds: device.expectedIntervalSeconds,
  );
}
