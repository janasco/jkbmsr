import 'dart:typed_data';

import 'package:bms_core/src/models/bms_models.dart';
import 'package:bms_core/src/protocols/bms_protocol.dart';

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

/// Central registry: detection signatures and helpers.
///
/// This is the pure-Dart half of the app-side `BrandRegistry`. The Flutter
/// presentation half — `BrandDesign` with its accent `Color` and `IconData`,
/// and the `_designs` catalog — stays in the shipping apps, because a model
/// layer with no UI has no use for a palette. Everything here is detection
/// and protocol reasoning and carries no Flutter dependency.
///
/// All service/char UUIDs and probe frames below are the exact ones already
/// verified against the syssi/esphome-*-bms component sources (see
/// lib/protocols/bms_protocol.dart) — nothing here invents protocol bytes.
class BrandRegistry {
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

  static BrandSignature? signatureFor(BmsBrand brand) {
    for (final s in _signatures) {
      if (s.brand == brand) return s;
    }
    return null;
  }

  /// Every brand with an implemented detection signature, in presentation
  /// order. This is the set the detection engine ranks against — it is
  /// deliberately *not* filtered by [BmsBrandVisibility.isPublic].
  static List<BmsBrand> get supportedBrands => _orderedBrands;

  /// Brands JKBMSR publicly supports and will present to a user. JK-BMS only.
  ///
  /// This is the *presentation* set — it drives the welcome screen, brand
  /// hero strips and any picker. It must NOT be used for detection: the
  /// detection engine and [serviceSharingCount] deliberately consider every
  /// implemented brand, because 0xFFE0 and 0xFF00 are each shared by several
  /// protocols and a non-JK device has to keep its own identity.
  static List<BmsBrand> get selectableBrands =>
      _orderedBrands.where((b) => b.isPublic).toList(growable: false);

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
