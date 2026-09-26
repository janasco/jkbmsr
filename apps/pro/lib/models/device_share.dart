/// A view-only grant of a gateway to another JKBMSR account.
/// Maps exactly to entries in the `/api/v1/dashboard/devices/:deviceId/shares`
/// response schema.
class DeviceShare {
  final String userId;
  final String email;
  final String sharedAt;

  DeviceShare({
    required this.userId,
    required this.email,
    required this.sharedAt,
  });

  factory DeviceShare.fromJson(Map<String, dynamic> json) {
    return DeviceShare(
      userId: json['userId'] as String,
      email: json['email'] as String,
      sharedAt: json['sharedAt'] as String? ?? '',
    );
  }
}
