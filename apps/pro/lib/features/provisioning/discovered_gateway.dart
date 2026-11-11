/// A gateway seen advertising its setup service.
///
/// Only gateways that are **not** configured advertise, so everything the scan
/// returns is a gateway that wants setting up. `rssi` is used for the signal
/// hint and to order the list: the nearest one is the one the user is standing
/// next to.
class DiscoveredGateway {
  const DiscoveredGateway({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Platform BLE identifier (MAC on Android). Never shown to the user.
  final String id;

  /// Advertised name, `JKBMSR-Setup-XXXX`.
  final String name;

  /// Received signal strength in dBm (negative).
  final int rssi;

  /// The four characters the user recognises on the board label, when the name
  /// carries them.
  String get shortCode {
    final parts = name.split('-');
    return parts.length >= 3 ? parts.last : name;
  }

  /// Three steps, coarse on purpose: an exact dBm figure invites the user to
  /// walk around optimising a number that does not matter. What matters is
  /// "close enough to set up".
  int get signalBars {
    if (rssi >= -60) return 3;
    if (rssi >= -78) return 2;
    return 1;
  }
}
