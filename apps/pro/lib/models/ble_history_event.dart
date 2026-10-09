/// A single successful BLE poll, reused from telemetry rather than a
/// separate history table. Maps exactly to the
/// `/v1/dashboard/devices/:deviceId/ble/history` response schema
/// (same endpoint jkbmsr-web's BlePollHistoryPanel uses).
class BleHistoryEvent {
  final String timestamp;
  final String address;
  final String advertisedName;
  final int rssi;
  final String hardwareVersion;
  final String softwareVersion;
  final int framesDecoded;
  final bool readOnly;

  BleHistoryEvent({
    required this.timestamp,
    required this.address,
    required this.advertisedName,
    required this.rssi,
    required this.hardwareVersion,
    required this.softwareVersion,
    required this.framesDecoded,
    required this.readOnly,
  });

  factory BleHistoryEvent.fromJson(Map<String, dynamic> json) {
    return BleHistoryEvent(
      timestamp: json['timestamp'] as String? ?? '',
      address: json['address'] as String? ?? '',
      advertisedName: json['advertisedName'] as String? ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? -128,
      hardwareVersion: json['hardwareVersion'] as String? ?? '',
      softwareVersion: json['softwareVersion'] as String? ?? '',
      framesDecoded: (json['framesDecoded'] as num?)?.toInt() ?? 0,
      readOnly: json['readOnly'] as bool? ?? true,
    );
  }
}
