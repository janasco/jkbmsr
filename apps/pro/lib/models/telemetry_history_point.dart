/// One point of the free, ungated short-term telemetry trend (jkbmsr-api's
/// `/telemetry/history` route — distinct from the paid Cloud Service
/// `/telemetry/monthly-history` route behind CloudHistoryPoint). Used to
/// draw the small trend sparklines on the Gauge & Sparkline / Icon Tiles
/// dashboard templates. Unlike CloudHistoryPoint's downsampled averages,
/// every row here is a real telemetry sample, so fields are never null.
class TelemetryHistoryPoint {
  final String timestamp;
  final double voltage;
  final double current;
  final double power;

  TelemetryHistoryPoint({
    required this.timestamp,
    required this.voltage,
    required this.current,
    required this.power,
  });

  factory TelemetryHistoryPoint.fromJson(Map<String, dynamic> json) {
    return TelemetryHistoryPoint(
      timestamp: json['timestamp'] as String? ?? '',
      voltage: (json['voltage'] as num? ?? 0).toDouble(),
      current: (json['current'] as num? ?? 0).toDouble(),
      power: (json['power'] as num? ?? 0).toDouble(),
    );
  }
}
