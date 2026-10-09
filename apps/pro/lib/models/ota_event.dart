/// Data model representing a single gateway OTA event/log.
/// Maps exactly to the `/v1/dashboard/devices/:deviceId/ota/history` response schema.
class OtaEvent {
  final int id;
  final String lastResult;
  final String offeredVersion;
  final bool lastCheckSucceeded;
  final bool updateAvailable;
  final bool updateApplied;
  final String createdAt;

  OtaEvent({
    required this.id,
    required this.lastResult,
    required this.offeredVersion,
    required this.lastCheckSucceeded,
    required this.updateAvailable,
    required this.updateApplied,
    required this.createdAt,
  });

  factory OtaEvent.fromJson(Map<String, dynamic> json) {
    return OtaEvent(
      id: json['id'] as int? ?? 0,
      lastResult: json['lastResult'] as String? ?? 'idle',
      offeredVersion: json['offeredVersion'] as String? ?? '',
      lastCheckSucceeded: json['lastCheckSucceeded'] as bool? ?? false,
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      updateApplied: json['updateApplied'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lastResult': lastResult,
      'offeredVersion': offeredVersion,
      'lastCheckSucceeded': lastCheckSucceeded,
      'updateAvailable': updateAvailable,
      'updateApplied': updateApplied,
      'createdAt': createdAt,
    };
  }
}
