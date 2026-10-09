/// Data model representing a published firmware release, mirroring the same
/// release-visibility data shown on the web dashboard.
/// Maps exactly to the `/v1/dashboard/firmware/releases` response list item schema.
class FirmwareRelease {
  final int id;
  final String version;
  final String targetHardware;
  final String rolloutChannel;
  final String releasedAt;
  final bool isLatest;
  final String? signingKeyId;
  final String? signatureAlgorithm;
  final String publicMirrorStatus;
  final String publicMirrorDetail;

  FirmwareRelease({
    required this.id,
    required this.version,
    required this.targetHardware,
    required this.rolloutChannel,
    required this.releasedAt,
    required this.isLatest,
    this.signingKeyId,
    this.signatureAlgorithm,
    required this.publicMirrorStatus,
    required this.publicMirrorDetail,
  });

  factory FirmwareRelease.fromJson(Map<String, dynamic> json) {
    return FirmwareRelease(
      id: (json['id'] as num? ?? 0).toInt(),
      version: json['version'] as String? ?? '',
      targetHardware: json['targetHardware'] as String? ?? '',
      rolloutChannel: json['rolloutChannel'] as String? ?? 'stable',
      releasedAt: json['releasedAt'] as String? ?? '',
      isLatest: json['isLatest'] as bool? ?? false,
      signingKeyId: json['signingKeyId'] as String?,
      signatureAlgorithm: json['signatureAlgorithm'] as String?,
      publicMirrorStatus: json['publicMirrorStatus'] as String? ?? 'unavailable',
      publicMirrorDetail: json['publicMirrorDetail'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'targetHardware': targetHardware,
      'rolloutChannel': rolloutChannel,
      'releasedAt': releasedAt,
      'isLatest': isLatest,
      'signingKeyId': signingKeyId,
      'signatureAlgorithm': signatureAlgorithm,
      'publicMirrorStatus': publicMirrorStatus,
      'publicMirrorDetail': publicMirrorDetail,
    };
  }
}
