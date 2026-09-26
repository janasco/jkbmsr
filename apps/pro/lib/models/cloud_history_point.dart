/// One point of Cloud Service long-term telemetry history (up to 365 days,
/// served from the Proxmox connector via jkbmsr-api's
/// `/telemetry/monthly-history` route). Nullable fields because a
/// downsampled bucket can legitimately average out to null (e.g. a device
/// that never reports temperature2) — unlike real-time Telemetry, which is
/// always fully populated.
class CloudHistoryPoint {
  final String timestamp;
  final double? voltage;
  final double? current;
  final double? soc;
  final double? power;
  final double? temperature1;
  final double? temperature2;

  CloudHistoryPoint({
    required this.timestamp,
    required this.voltage,
    required this.current,
    required this.soc,
    required this.power,
    required this.temperature1,
    required this.temperature2,
  });

  factory CloudHistoryPoint.fromJson(Map<String, dynamic> json) {
    return CloudHistoryPoint(
      timestamp: json['timestamp'] as String? ?? '',
      voltage: (json['voltage'] as num?)?.toDouble(),
      current: (json['current'] as num?)?.toDouble(),
      soc: (json['soc'] as num?)?.toDouble(),
      power: (json['power'] as num?)?.toDouble(),
      temperature1: (json['temperature1'] as num?)?.toDouble(),
      temperature2: (json['temperature2'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'voltage': voltage,
        'current': current,
        'soc': soc,
        'power': power,
        'temperature1': temperature1,
        'temperature2': temperature2,
      };
}
