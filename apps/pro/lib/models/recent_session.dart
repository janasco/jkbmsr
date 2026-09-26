/// A recent sign-in for the account, doubling as a live/revocable session
/// when the backend tracked it (see jkbmsr-api's GET /user/sessions). Maps
/// exactly to that endpoint's response schema.
class RecentSession {
  final String id;
  final String method;
  final String? ipAddress;
  final String? userAgent;
  final String? location;
  final String createdAt;
  final bool isCurrent;
  final bool revoked;
  final bool expired;

  RecentSession({
    required this.id,
    required this.method,
    required this.ipAddress,
    required this.userAgent,
    required this.location,
    required this.createdAt,
    required this.isCurrent,
    required this.revoked,
    required this.expired,
  });

  factory RecentSession.fromJson(Map<String, dynamic> json) {
    return RecentSession(
      id: json['id'] as String? ?? '',
      method: json['method'] as String? ?? '',
      ipAddress: json['ipAddress'] as String?,
      userAgent: json['userAgent'] as String?,
      location: json['location'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
      isCurrent: json['isCurrent'] as bool? ?? false,
      revoked: json['revoked'] as bool? ?? false,
      expired: json['expired'] as bool? ?? false,
    );
  }
}
