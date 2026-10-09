/// One 2.4 GHz network the gateway saw in its last scan.
/// Maps exactly to entries in the wifi.networks response array.
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;

  WifiNetwork({required this.ssid, required this.rssi, required this.secure});

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] as String? ?? '',
      rssi: (json['rssi'] as num? ?? 0).toInt(),
      secure: json['secure'] == true,
    );
  }
}

/// The gateway's WiFi status plus any in-flight scan/change request.
/// Maps exactly to the `/v1/dashboard/devices/:deviceId/wifi` response
/// schema — scan and change are both async (the gateway picks the request
/// up on its own poll cycle), so this is a snapshot to be re-fetched, not a
/// synchronous result.
class DeviceWifiState {
  final String currentSsid;
  final String? scanRequestId;
  final String? scanRequestedAt;
  final String? scanCompletedAt;
  final List<WifiNetwork> networks;
  final String? changeRequestId;
  final String? candidateSsid;
  // 'idle' | 'pending' | 'applying' | 'succeeded' | 'failed'
  final String changeStatus;
  final String changeMessage;
  final String? changeRequestedAt;
  final String? changeCompletedAt;

  DeviceWifiState({
    required this.currentSsid,
    this.scanRequestId,
    this.scanRequestedAt,
    this.scanCompletedAt,
    required this.networks,
    this.changeRequestId,
    this.candidateSsid,
    required this.changeStatus,
    required this.changeMessage,
    this.changeRequestedAt,
    this.changeCompletedAt,
  });

  bool get isPending =>
      (scanRequestId != null && scanCompletedAt == null) || changeStatus == 'pending' || changeStatus == 'applying';

  factory DeviceWifiState.fromJson(Map<String, dynamic> json) {
    final networksList = json['networks'] as List<dynamic>? ?? [];
    return DeviceWifiState(
      currentSsid: json['currentSsid'] as String? ?? '',
      scanRequestId: json['scanRequestId'] as String?,
      scanRequestedAt: json['scanRequestedAt'] as String?,
      scanCompletedAt: json['scanCompletedAt'] as String?,
      networks: networksList.map((item) => WifiNetwork.fromJson(item as Map<String, dynamic>)).toList(),
      changeRequestId: json['changeRequestId'] as String?,
      candidateSsid: json['candidateSsid'] as String?,
      changeStatus: json['changeStatus'] as String? ?? 'idle',
      changeMessage: json['changeMessage'] as String? ?? '',
      changeRequestedAt: json['changeRequestedAt'] as String?,
      changeCompletedAt: json['changeCompletedAt'] as String?,
    );
  }
}
