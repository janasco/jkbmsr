/// The persistent remote Wi-Fi target an owner sets from the cloud, plus the
/// gateway's last cloud-reported Wi-Fi state and the unreachable-alert episode.
///
/// Maps exactly to the `/v1/dashboard/devices/:deviceId/wifi/target`
/// response schema (see jkbmsr-api's routes/dashboard.ts +
/// services/wifiConfigs.ts). This is the "set it and forget it" counterpart to
/// the interactive `/wifi/change` flow: it is stored server-side and re-sent on
/// every gateway config poll so the gateway keeps retrying it across reboots.
///
/// There is deliberately no password field anywhere in this model. The backend
/// encrypts the password at rest and maps it away entirely for the owner
/// (`mapOwnerWifiTarget`), so it is never echoed back to the app — the only
/// copy held here is the one the owner types before a single PUT.
class WifiTarget {
  final String ssid;
  final bool isOpen;
  final String? revision;
  final String? setAt;

  WifiTarget({
    required this.ssid,
    required this.isOpen,
    this.revision,
    this.setAt,
  });

  factory WifiTarget.fromJson(Map<String, dynamic> json) {
    return WifiTarget(
      ssid: json['ssid'] as String? ?? '',
      isOpen: json['isOpen'] == true,
      revision: json['revision'] as String?,
      setAt: json['setAt'] as String?,
    );
  }
}

/// The gateway's last Wi-Fi state as reported on a normal check-in. Only
/// present once the gateway has actually checked in; `null` when it never has.
class WifiReported {
  final String ssid;
  // 'connected' | 'connecting' | 'no_internet' | 'auth_failed' | 'no_ap' | 'open'
  final String state;
  final String error;
  final String? at;
  /// True when the current network was set up on site rather than by a cloud
  /// target — the backend then treats the on-site fix as authoritative.
  final bool localProvisioned;

  WifiReported({
    required this.ssid,
    required this.state,
    required this.error,
    this.at,
    this.localProvisioned = false,
  });

  factory WifiReported.fromJson(Map<String, dynamic> json) {
    return WifiReported(
      ssid: json['ssid'] as String? ?? '',
      state: json['state'] as String? ?? '',
      error: json['error'] as String? ?? '',
      at: json['at'] as String?,
      localProvisioned: json['localProvisioned'] == true,
    );
  }

  /// Human-readable form of [state]. Unknown values fall through unchanged so
  /// a future firmware state is shown honestly rather than mislabelled.
  String get stateLabel {
    switch (state) {
      case 'connected':
        return 'Connected';
      case 'connecting':
        return 'Connecting';
      case 'no_internet':
        return 'Connected, no internet';
      case 'auth_failed':
        return 'Wrong password';
      case 'no_ap':
        return 'Network not found';
      case 'open':
        return 'Connected (open network)';
      default:
        return state.isEmpty ? 'Unknown' : state;
    }
  }
}

/// State of the "gateway can't reach the network you set" alert episode.
/// Absence-based: the backend can't be told by the gateway in real time, so an
/// active episode means the gateway has gone silent since the target was set.
///
/// [acknowledgedAt] and [muted] are the owner's controls over that episode
/// (see jkbmsr-api's dashboard.ts): acknowledging silences this outage until it
/// clears or the owner re-enables it, and muting silences all offline alerts for
/// this gateway until unmuted. Both are parsed defensively — an older API build
/// that predates them omits the keys entirely, and absence must read as
/// "not acknowledged / not muted", never as a reason to hide the controls.
class WifiAlertState {
  final bool active;
  final String? lastSentAt;
  final int count;
  final bool muted;
  final String? acknowledgedAt;

  const WifiAlertState({
    required this.active,
    this.lastSentAt,
    required this.count,
    this.muted = false,
    this.acknowledgedAt,
  });

  factory WifiAlertState.fromJson(Map<String, dynamic> json) {
    return WifiAlertState(
      active: json['active'] == true,
      lastSentAt: json['lastSentAt'] as String?,
      count: (json['count'] as num? ?? 0).toInt(),
      muted: json['muted'] == true,
      // A non-string here (e.g. an integer timestamp from a future API shape)
      // must read as "not acknowledged" rather than crashing the whole target
      // response — the controls then simply don't render, which is safe.
      acknowledgedAt:
          json['acknowledgedAt'] is String ? json['acknowledgedAt'] as String : null,
    );
  }

  /// Returns a copy with the given fields replaced. Because
  /// [acknowledgedAt] is nullable, pass [clearAcknowledgedAt] to set it to
  /// null explicitly (a plain `copyWith(acknowledgedAt: null)` would be
  /// indistinguishable from "leave it alone").
  WifiAlertState copyWith({
    bool? active,
    String? lastSentAt,
    int? count,
    bool? muted,
    String? acknowledgedAt,
    bool clearAcknowledgedAt = false,
  }) {
    return WifiAlertState(
      active: active ?? this.active,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      count: count ?? this.count,
      muted: muted ?? this.muted,
      acknowledgedAt:
          clearAcknowledgedAt ? null : (acknowledgedAt ?? this.acknowledgedAt),
    );
  }
}

/// The full `.../wifi/target` response: what the owner asked for, what the
/// gateway last reported, and whether the unreachable alert is firing.
class DeviceWifiTargetState {
  final WifiTarget? target;
  final WifiReported? reported;
  final WifiAlertState alert;

  DeviceWifiTargetState({
    required this.target,
    required this.reported,
    required this.alert,
  });

  factory DeviceWifiTargetState.fromJson(Map<String, dynamic> json) {
    final targetJson = json['target'];
    final reportedJson = json['reported'];
    final alertJson = json['alert'];
    return DeviceWifiTargetState(
      target: targetJson is Map<String, dynamic> ? WifiTarget.fromJson(targetJson) : null,
      reported: reportedJson is Map<String, dynamic> ? WifiReported.fromJson(reportedJson) : null,
      alert: alertJson is Map<String, dynamic>
          ? WifiAlertState.fromJson(alertJson)
          : WifiAlertState(active: false, count: 0),
    );
  }
}
