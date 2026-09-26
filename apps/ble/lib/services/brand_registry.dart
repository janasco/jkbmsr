import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/bms_models.dart';
import '../protocols/bms_protocol.dart';

/// Permanent visual identity for one supported BMS brand. Every screen that
/// shows a device uses this so the whole app adapts its accent, label and
/// icon to whichever brand is connected or detected in range.
class BrandDesign {
  final BmsBrand brand;

  /// Marketing name, e.g. "JK-BMS".
  final String name;

  /// Compact tag used for badges, e.g. "JK".
  final String tag;

  /// One-line description shown on the welcome/detection screens.
  final String tagline;

  /// Brand accent color. Accent chips/backgrounds derive their tint from it
  /// via [`Color.withValues`], so it reads on both themes without extra work.
  final Color accent;

  final IconData icon;

  const BrandDesign({
    required this.brand,
    required this.name,
    required this.tag,
    required this.tagline,
    required this.accent,
    required this.icon,
  });
}

/// Static, byte-verified detection signature for one BMS brand: which name
/// patterns and GATT service UUIDs identify it, and — when the brand has a
/// sane, verifiable request command — what to send to make it identify
/// itself by responding with a real telemetry frame. A null
/// [probeRequest] marks a brand that can't be probed (Offgridtec needs a
/// per-device encryption key; Topband streams passively and needs a
/// different notification characteristic than its protocol-family peers).
class BrandSignature {
  final BmsBrand brand;

  /// Prefixes matched against the lower-cased device name.
  final List<String> namePrefixes;

  /// Substrings matched against the lower-cased device name.
  final List<String> nameContains;

  /// Full 128-bit GATT service UUIDs (already lower-cased).
  final Set<String> serviceUuids;

  /// Builds the "are you really a `<brand>`" request frame. Null when the
  /// brand can't respond to such a probe.
  final Uint8List? Function()? probeRequest;

  const BrandSignature({
    required this.brand,
    this.namePrefixes = const [],
    this.nameContains = const [],
    this.serviceUuids = const {},
    this.probeRequest,
  });

  bool matchesName(String lowerName) {
    for (final p in namePrefixes) {
      if (lowerName.startsWith(p)) return true;
    }
    for (final c in nameContains) {
      if (lowerName.contains(c)) return true;
    }
    return false;
  }
}

/// Central registry: brand identity, detection signatures, and helpers.
///
/// All service/char UUIDs and probe frames below are the exact ones already
/// verified against the syssi/esphome-*-bms component sources (see
/// lib/protocols/bms_protocol.dart) — nothing here invents protocol bytes.
class BrandRegistry {
  static const List<BrandDesign> _designs = [
    BrandDesign(
      brand: BmsBrand.jkbms,
      name: 'JK-BMS',
      tag: 'JK',
      tagline: 'Active balancer & BMS with full switch and settings control',
      accent: Color(0xFF10B981),
      icon: Icons.bolt_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.daly,
      name: 'Daly Smart BMS',
      tag: 'DALY',
      tagline: 'Modbus-style (D2) BMS with charge, discharge and balancer control',
      accent: Color(0xFF14B8A6),
      icon: Icons.battery_charging_full_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.jbd,
      name: 'JBD / Xiaoxiang',
      tag: 'JBD',
      tagline: 'Xiaoxiang-family BMS with combined MOSFET control',
      accent: Color(0xFF3B82F6),
      icon: Icons.speed_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.ant,
      name: 'ANT BMS',
      tag: 'ANT',
      tagline: 'BLE BMS with turn-on/turn-off switch registers',
      accent: Color(0xFF8B5CF6),
      icon: Icons.wifi_tethering_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.seplos,
      name: 'Seplos Balancer',
      tag: 'SEPLOS',
      tagline: 'Active balancer with MOSFET charge/discharge control',
      accent: Color(0xFFF59E0B),
      icon: Icons.balance_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.tianpower,
      name: 'Tianpower',
      tag: 'TP',
      tagline: 'Monitoring-only BMS (no switch or settings writes)',
      accent: Color(0xFF0EA5E9),
      icon: Icons.flash_on_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.basen,
      name: 'Basen BMS',
      tag: 'BASEN',
      tagline: 'BLE BMS with shared charge/discharge holding register',
      accent: Color(0xFFF43F5E),
      icon: Icons.energy_savings_leaf_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.ks,
      name: 'KS48100',
      tag: 'KS',
      tagline: '48V rack battery with configurable protection registers',
      accent: Color(0xFF6366F1),
      icon: Icons.storage_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.ogt,
      name: 'Offgridtec',
      tag: 'OGT',
      tagline: 'Detected by name only — protocol needs a per-device key',
      accent: Color(0xFF64748B),
      icon: Icons.offline_bolt_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.topband,
      name: 'Topband',
      tag: 'TOPBAND',
      tagline: 'Passive monitoring-only BMS (streams automatically)',
      accent: Color(0xFF84CC16),
      icon: Icons.donut_large_rounded,
    ),
    BrandDesign(
      brand: BmsBrand.lolan,
      name: 'Lolan',
      tag: 'LOLAN',
      tagline: 'Float32 telemetry with turn-on/turn-off switch commands',
      accent: Color(0xFF06B6D4),
      icon: Icons.bolt,
    ),
    BrandDesign(
      brand: BmsBrand.unknown,
      name: 'Unknown BMS',
      tag: 'BMS',
      tagline: 'Connected device is not yet recognized as a supported BMS',
      accent: Color(0xFF64748B),
      icon: Icons.help_outline_rounded,
    ),
  ];

  // Probe requests are closures (they build brand-specific frames), so this
  // catalog can't be a const list.
  static final List<BrandSignature> _signatures = [
    BrandSignature(
      brand: BmsBrand.jkbms,
      namePrefixes: ['jk', 'b1a', 'b2a', 'bd6a', 'pb2a'],
      nameContains: ['jkbms'],
      serviceUuids: {
        BmsProtocolHelper.jkBmsServiceUuid,
        BmsProtocolHelper.jk02ServiceUuid,
      },
      probeRequest: () => BmsProtocolHelper.buildJk02Command(
          BmsProtocolHelper.jk02CommandDeviceInfo),
    ),
    BrandSignature(
      brand: BmsBrand.daly,
      namePrefixes: ['dl'],
      nameContains: ['daly'],
      serviceUuids: {BmsProtocolHelper.dalyServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildDalyStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.jbd,
      namePrefixes: ['sp'],
      nameContains: ['xiaoxiang', 'jbd', 'smartbms'],
      serviceUuids: {BmsProtocolHelper.jbdServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildJbdReadCommand(
          BmsProtocolHelper.jbdCommandBasicInfo),
    ),
    BrandSignature(
      brand: BmsBrand.ant,
      namePrefixes: ['ant'],
      nameContains: ['antbms'],
      serviceUuids: {BmsProtocolHelper.antServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildAntStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.seplos,
      nameContains: ['seplos'],
      serviceUuids: {BmsProtocolHelper.seplosServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildSeplosStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.tianpower,
      nameContains: ['tianpower'],
      serviceUuids: {BmsProtocolHelper.tianpowerServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildTianpowerStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.basen,
      nameContains: ['basen'],
      serviceUuids: {BmsProtocolHelper.basenServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildBasenStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.ks,
      namePrefixes: ['ks-'],
      nameContains: ['ks48100'],
      serviceUuids: {BmsProtocolHelper.ksServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildKsStatusRequest(),
    ),
    BrandSignature(
      brand: BmsBrand.ogt,
      nameContains: ['offgridtec', 'ogt'],
      serviceUuids: {BmsProtocolHelper.dalyServiceUuid},
      probeRequest: null,
    ),
    BrandSignature(
      brand: BmsBrand.topband,
      nameContains: ['topband'],
      serviceUuids: {BmsProtocolHelper.topbandServiceUuid},
      probeRequest: null,
    ),
    BrandSignature(
      brand: BmsBrand.lolan,
      nameContains: ['lolan'],
      serviceUuids: {BmsProtocolHelper.lolanServiceUuid},
      probeRequest: () => BmsProtocolHelper.buildLolanCommand(
          BmsProtocolHelper.lolanCommandReqStatus),
    ),
  ];

  static const List<BmsBrand> _orderedBrands = [
    BmsBrand.jkbms,
    BmsBrand.daly,
    BmsBrand.jbd,
    BmsBrand.ant,
    BmsBrand.seplos,
    BmsBrand.tianpower,
    BmsBrand.basen,
    BmsBrand.ks,
    BmsBrand.ogt,
    BmsBrand.topband,
    BmsBrand.lolan,
  ];

  static BrandDesign designFor(BmsBrand brand) {
    for (final d in _designs) {
      if (d.brand == brand) return d;
    }
    return _designs.last;
  }

  static BrandSignature? signatureFor(BmsBrand brand) {
    for (final s in _signatures) {
      if (s.brand == brand) return s;
    }
    return null;
  }

  static List<BrandDesign> get supportedBrands => _orderedBrands
      .map(designFor)
      .toList(growable: false);

  /// Brands JKBMSR publicly supports and will present to a user. JK-BMS only.
  ///
  /// This is the *presentation* set — it drives the welcome screen, brand
  /// hero strips and any picker. It must NOT be used for detection: the
  /// detection engine and [serviceSharingCount] deliberately consider every
  /// implemented brand, because 0xFFE0 and 0xFF00 are each shared by several
  /// protocols and a non-JK device has to keep its own identity.
  static List<BrandDesign> get selectableBrands => _orderedBrands
      .where((b) => b.isPublic)
      .map(designFor)
      .toList(growable: false);

  /// Number of brands advertising [serviceUuid] — used to score a service
  /// match as exclusive (0.6) or shared (0.4).
  static int serviceSharingCount(String serviceUuid) {
    final lower = serviceUuid.toLowerCase();
    var count = 0;
    for (final s in _signatures) {
      if (s.serviceUuids.any((u) => u == lower)) count++;
    }
    return count;
  }

  /// Human, per-brand hint derived from the device model name (e.g.
  /// "JK_BD4A20S4P" -> "BD4A2 · 20S 4P"). Falls back to the raw model name
  /// for brands/names we have no parsing rule for.
  static String seriesHint(BmsBrand brand, String modelName) {
    if (brand == BmsBrand.jkbms) {
      final m = RegExp(r'^JK_([A-Za-z]+\d*[A-Za-z]?)(\d+)[Ss](?:(\d+)[Pp])?$')
          .firstMatch(modelName.trim());
      if (m != null) {
        final series = m.group(1) ?? '';
        final cells = m.group(2) ?? '';
        final parallel = m.group(3);
        final cellPart = cells + (parallel == null ? 'S' : 'S $parallel');
        return '$series · $cellPart';
      }
    }
    return modelName.isEmpty ? 'Unknown model' : modelName;
  }
}