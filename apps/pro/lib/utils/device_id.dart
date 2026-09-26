/// A compact, non-authoritative identifier for display only.
///
/// The API continues to use the full logical device UUID. This deterministic
/// hash keeps that UUID out of normal screens while remaining stable across
/// firmware updates and reflashes. Must stay bit-for-bit identical to
/// jkbmsr-web's `formatGatewayId` (src/lib/device-id.ts) — same 32-bit
/// FNV-1a hash, masked to 32 bits after every multiply to match JS's
/// Math.imul wraparound.
String formatGatewayId(String deviceId) {
  int hash = 0x811c9dc5;
  for (int i = 0; i < deviceId.length; i++) {
    hash ^= deviceId.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return 'GW-${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
