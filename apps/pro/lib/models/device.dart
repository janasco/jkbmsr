/// Data model representing a JKBMSR device.
/// Maps exactly to the `/api/v1/dashboard/devices` response schema.
class Device {
  final String id;
  final String name;
  final String status; // 'online', 'offline', 'warning', 'critical'
  final String targetHardware;
  final String otaChannel;
  final double soc;
  final double voltage;
  final double current;
  final String? firmwareVersion;
  final String lastSeen;
  final String? latestFirmwareVersion;
  final String? latestFirmwareReleasedAt;
  final bool updateAvailable;
  // Telemetry cadence for this gateway, server-resolved from its Cloud
  // Service tier. `expectedIntervalSeconds` is the gateway's own configured
  // interval; `secondsSinceLastTelemetry` is how long ago it last checked in;
  // `secondsUntilNextExpectedCheckIn` is the countdown the dashboard shows
  // (already floored at 0 server-side). All three are nullable because the
  // API omits them when the device has never reported telemetry — a fresh
  // claim or a gateway that just reconnected — and older API builds may not
  // send them at all. Do not treat null as zero.
  final int? expectedIntervalSeconds;
  final int? secondsSinceLastTelemetry;
  final int? secondsUntilNextExpectedCheckIn;
  // False when this gateway was shared to the signed-in account rather than
  // owned by it — gates settings/rename/delete/sharing controls in the UI
  // (the API independently refuses those for non-owners regardless).
  final bool isOwner;
  final String? ownerEmail;
  // Only present on the single-device detail response (GET
  // /devices/:deviceId) — picks which dashboard layout the battery
  // dashboard screen renders. Independent of jkbmsr-web's own template
  // choice (dashboardTemplateWeb) as of jkbmsr-api's device_configs split —
  // picking a layout in this app no longer overwrites what the web
  // dashboard shows, and vice versa. Falls back to 'default' both when
  // absent (shared-viewer/list responses don't include it) and when set to
  // a web-only template key mobile hasn't ported a renderer for yet.
  final String dashboardTemplateMobile;

  Device({
    required this.id,
    required this.name,
    required this.status,
    required this.targetHardware,
    required this.otaChannel,
    required this.soc,
    required this.voltage,
    required this.current,
    this.firmwareVersion,
    required this.lastSeen,
    this.latestFirmwareVersion,
    this.latestFirmwareReleasedAt,
    required this.updateAvailable,
    this.expectedIntervalSeconds,
    this.secondsSinceLastTelemetry,
    this.secondsUntilNextExpectedCheckIn,
    this.isOwner = true,
    this.ownerEmail,
    this.dashboardTemplateMobile = 'default',
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      status: json['status'] as String? ?? 'offline',
      targetHardware: json['targetHardware'] as String? ?? 'esp32dev',
      otaChannel: json['otaChannel'] as String? ?? 'stable',
      soc: (json['soc'] as num? ?? 0).toDouble(),
      voltage: (json['voltage'] as num? ?? 0).toDouble(),
      current: (json['current'] as num? ?? 0).toDouble(),
      firmwareVersion: json['firmwareVersion'] as String?,
      lastSeen: json['lastSeen'] as String? ?? '',
      latestFirmwareVersion: json['latestFirmwareVersion'] as String?,
      latestFirmwareReleasedAt: json['latestFirmwareReleasedAt'] as String?,
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      // `as num?` tolerates the API sending a double, and a missing key is
      // null rather than 0 — the UI must be able to tell "no countdown"
      // (never reported telemetry) from "due now" (0 seconds left).
      expectedIntervalSeconds: (json['expectedIntervalSeconds'] as num?)?.toInt(),
      secondsSinceLastTelemetry: (json['secondsSinceLastTelemetry'] as num?)?.toInt(),
      secondsUntilNextExpectedCheckIn: (json['secondsUntilNextExpectedCheckIn'] as num?)?.toInt(),
      isOwner: json['isOwner'] as bool? ?? true,
      ownerEmail: json['ownerEmail'] as String?,
      dashboardTemplateMobile: json['dashboardTemplateMobile'] as String? ?? 'default',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'targetHardware': targetHardware,
      'otaChannel': otaChannel,
      'soc': soc,
      'voltage': voltage,
      'current': current,
      'firmwareVersion': firmwareVersion,
      'lastSeen': lastSeen,
      'latestFirmwareVersion': latestFirmwareVersion,
      'latestFirmwareReleasedAt': latestFirmwareReleasedAt,
      'updateAvailable': updateAvailable,
      'expectedIntervalSeconds': expectedIntervalSeconds,
      'secondsSinceLastTelemetry': secondsSinceLastTelemetry,
      'secondsUntilNextExpectedCheckIn': secondsUntilNextExpectedCheckIn,
      'isOwner': isOwner,
      'ownerEmail': ownerEmail,
      'dashboardTemplateMobile': dashboardTemplateMobile,
    };
  }
}
