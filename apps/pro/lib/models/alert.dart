/// Data model representing a gateway/battery alert.
/// Maps exactly to the `/v1/dashboard/alerts` response list item schema.
class Alert {
  final String id;
  final String deviceId;
  final String deviceName;
  final String severity; // 'warning', 'critical'
  final String message;
  final String createdAt;
  final bool isResolved;
  final String? resolvedAt;

  Alert({
    required this.id,
    this.deviceId = '',
    required this.deviceName,
    required this.severity,
    required this.message,
    required this.createdAt,
    this.isResolved = false,
    this.resolvedAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
      severity: json['severity'] as String? ?? 'warning',
      message: json['message'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      isResolved: json['isResolved'] as bool? ?? false,
      resolvedAt: json['resolvedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'severity': severity,
      'message': message,
      'createdAt': createdAt,
      'isResolved': isResolved,
      'resolvedAt': resolvedAt,
    };
  }
}
