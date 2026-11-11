import 'dart:convert';
import 'dart:typed_data';

/// The gateway's BLE setup protocol, from the app's side.
///
/// The contract is `firmware/docs/ble-provisioning.md`; this class encodes to it
/// and is deliberately free of `universal_ble` types, so the parts that can be
/// wrong in a way a human would never notice (offsets, chunk boundaries, a
/// half-written payload) are testable on the host.
class ProvisioningProtocol {
  ProvisioningProtocol._();

  static const service = '9a1f0000-7c3b-4d2e-9f10-6b5a8e2c4d70';
  static const statusCharacteristic = '9a1f0001-7c3b-4d2e-9f10-6b5a8e2c4d70';
  static const setupCharacteristic = '9a1f0002-7c3b-4d2e-9f10-6b5a8e2c4d70';
  static const payloadCharacteristic = '9a1f0003-7c3b-4d2e-9f10-6b5a8e2c4d70';
  static const commandCharacteristic = '9a1f0004-7c3b-4d2e-9f10-6b5a8e2c4d70';

  /// Advertised name prefix. The four characters after it are the short code
  /// the app shows, so a user can match the phone to the board.
  static const namePrefix = 'JKBMSR-Setup-';

  /// The firmware refuses a payload larger than this, because it holds the whole
  /// configuration in one buffer.
  static const maxPayloadBytes = 768;

  /// Bytes per write, before the two-byte offset. 180 plus 2 stays inside a
  /// 183-byte ATT payload, which every Android device negotiates.
  static const chunkSize = 180;

  static const commitCommand = 'commit';

  /// The JSON body the firmware validates. Keys are part of the contract, so
  /// they are constants rather than string literals at the call site.
  static Uint8List encodePayload({
    required String ssid,
    required String password,
    required String timeZone,
    required String claimToken,
  }) {
    final json = jsonEncode({
      'ssid': ssid,
      'password': password,
      'timeZone': timeZone,
      'claimToken': claimToken,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Splits the payload into offset-addressed writes.
  ///
  /// Each chunk is `[offset lo, offset hi, ...bytes]`. The firmware assembles by
  /// offset rather than by arrival order, so a lost or reordered write is a
  /// visible gap at commit instead of a corrupted SSID.
  static List<Uint8List> chunks(Uint8List payload, {int size = chunkSize}) {
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'must not be empty');
    }
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'exceeds the $maxPayloadBytes-byte device buffer',
      );
    }
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'must be positive');
    }

    final out = <Uint8List>[];
    for (var offset = 0; offset < payload.length; offset += size) {
      final end = (offset + size < payload.length) ? offset + size : payload.length;
      final chunk = Uint8List(2 + (end - offset));
      chunk[0] = offset & 0xff;
      chunk[1] = (offset >> 8) & 0xff;
      chunk.setRange(2, chunk.length, payload, offset);
      out.add(chunk);
    }
    return out;
  }

  /// A POSIX TZ string, validated the way the firmware validates it.
  ///
  /// The device has no time zone database, so an IANA name is not a value it can
  /// apply: libc ignores it silently and keeps printing UTC while the settings
  /// page says otherwise. Rejecting it here is the only place the user can be
  /// told why.
  static bool isValidTimeZone(String value) {
    if (value.isEmpty || value.length > 48) return false;
    // A slash is legal only inside a DST rule time ("M10.5.0/3"), which can only
    // appear after a comma. "Asia/Manila" fails exactly here.
    if (value.contains('/') && !value.contains(',')) return false;
    return RegExp(r'^[A-Za-z0-9+\-:,./<>]+$').hasMatch(value);
  }

  /// Three dot-separated, non-empty segments. A shape check, not a signature
  /// check: the server verifies the token, but a wrong string should fail on the
  /// phone rather than as a 401 after the gateway has already restarted.
  static bool isPlausibleClaimToken(String value) {
    if (value.isEmpty || value.length > 512) return false;
    final parts = value.split('.');
    return parts.length == 3 && parts.every((p) => p.isNotEmpty);
  }

  static bool isValidSetupCode(String value) =>
      RegExp(r'^\d{6}$').hasMatch(value);

  /// One of the firmware's states, or `failed:<reason>`. Anything unrecognised
  /// becomes [ProvisioningStatus.unknown], never [done]: a status string this
  /// app does not know is not evidence that setup succeeded.
  static ProvisioningStatus parseStatus(String raw) {
    final text = raw.trim();
    switch (text) {
      case 'advertising':
        return ProvisioningStatus.advertising;
      case 'connected':
        return ProvisioningStatus.connected;
      case 'authenticated':
        return ProvisioningStatus.authenticated;
      case 'applying':
        return ProvisioningStatus.applying;
      case 'rebooting':
        return ProvisioningStatus.rebooting;
      case 'registering':
        return ProvisioningStatus.registering;
      case 'running':
        return ProvisioningStatus.done;
    }
    if (text.startsWith('failed:')) return ProvisioningStatus.failed;
    return ProvisioningStatus.unknown;
  }
}

enum ProvisioningStatus {
  advertising,
  connected,
  authenticated,
  applying,
  rebooting,
  registering,
  done,
  failed,
  unknown,
}
