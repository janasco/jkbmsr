import 'dart:convert';
import 'dart:math';

import 'package:bms_core/bms_core.dart';

import 'contribution_selection.dart';

/// The versioned donation payload — the exact JSON a Contributor capture
/// produces, and the shape the backend stores.
///
/// Versioning (plan §4): the top-level [currentSchemaVersion] is a **string**.
/// Additive changes bump the minor (`"1"` -> `"1.1"`); breaking changes bump
/// the major (`"1"` -> `"2"`). The server stores the version verbatim and
/// tolerates unknown fields; the client always writes its *own* current
/// version. [decode] accepts any `1.x` document and rejects an unknown major.
///
/// Privacy (plan §4, "Anonymisation rules"). This model is the allowlist: it
/// is the only thing that can be serialised, and its defaults are the
/// redacted ones. In particular:
///
///  * [contributionId] is a random UUIDv7, never derived from the device or
///    the user.
///  * The serial number is **withheld by default** ([serialHash] is null and
///    [RedactionInfo.serialNumber] is `"withheld"`); it is only carried when
///    the user explicitly opts in, and the server hashes and discards it.
///  * The manufacturing date is truncated to a year-month.
///  * The Bluetooth address keeps only the vendor OUI; the host part is
///    zeroed.
///  * The advertised name is reduced to a short prefix plus a wildcard.
///  * `powerOnCount` and RSSI are bucketed, never exact.
///  * There are no user identifiers of any kind.
///
/// All numeric telemetry names its SI unit (`voltageV`, `currentA`, `tempC`,
/// `capacityAh`); timestamps are UTC ISO-8601.
class Contribution {
  /// The schema version this client writes. See the class docs for the
  /// additive-minor / breaking-major rule.
  static const String currentSchemaVersion = '1';

  /// The major version this client can read and write.
  static const int supportedMajorVersion = 1;

  /// Hard cap on the serialised payload (plan §4, "Size discipline").
  static const int maxPayloadBytes = 256 * 1024;

  /// Hard cap on the number of raw frames carried (newest kept).
  static const int maxRawFrames = 200;

  /// The version read from (or written to) the document. On [toJson] this is
  /// always rewritten to [currentSchemaVersion]; a decoded older minor keeps
  /// its incoming value in this field but re-encodes as current.
  final String schemaVersion;
  final String contributionId;
  final DateTime capturedAt;
  final AppProvenance app;
  final ConsentRecord? consent;
  final BmsProvenance bms;
  final AdvertisementInfo advertisement;
  final List<TelemetrySample> samples;
  final SettingsCapture? settings;
  final LogbookCapture? logbook;
  final List<RawFrame> rawFrames;
  final RedactionInfo redaction;

  /// Payload size in bytes, measured before the `sizeBytes` field itself is
  /// added. Informational: the authoritative size is [encodedBytes].
  final int? sizeBytes;

  const Contribution({
    required this.contributionId,
    required this.capturedAt,
    required this.app,
    required this.bms,
    required this.advertisement,
    required this.samples,
    required this.redaction,
    this.schemaVersion = currentSchemaVersion,
    this.consent,
    this.settings,
    this.logbook,
    this.rawFrames = const [],
    this.sizeBytes,
  });

  /// Builds a payload from a live capture, applying every anonymisation
  /// default. Pass [includeSerial] only when the user has explicitly opted in
  /// on the review screen (Phase 4); until then the serial is withheld.
  factory Contribution.fromCapture({
    required AppProvenance app,
    required String remoteId,
    required String advertisedName,
    required int rssi,
    required List<String> serviceUuids,
    required BmsModelInfo? deviceInfo,
    required bool is32s,
    required List<TelemetrySample> samples,
    List<RawFrame> rawFrames = const [],
    ConsentRecord? consent,
    Map<String, double>? settingsValues,
    DateTime? settingsCapturedAt,
    List<LogbookCaptureEntry>? logbookEntries,
    bool includeSerial = false,
    DateTime? capturedAt,
    String? contributionId,
    Random? random,
  }) {
    final captured = (capturedAt ?? DateTime.now()).toUtc();
    final lastSample = samples.isEmpty ? null : samples.last;
    final serial = deviceInfo?.serialNumber ?? '';
    final serialShared = includeSerial && serial.isNotEmpty;

    final uuids = serviceUuids.map((u) => u.toLowerCase()).toSet().toList()..sort();

    // Keep only the newest [maxRawFrames] frames.
    final frames = rawFrames.length > maxRawFrames
        ? rawFrames.sublist(rawFrames.length - maxRawFrames)
        : List<RawFrame>.unmodifiable(rawFrames);

    return Contribution(
      contributionId: contributionId ?? 'c_${uuidV7(random: random)}',
      capturedAt: captured,
      app: app,
      consent: consent,
      bms: BmsProvenance(
        brand: 'jkbms',
        modelName: deviceInfo?.modelName ?? '',
        hardwareVersion: deviceInfo?.hardwareVersion ?? '',
        softwareVersion: deviceInfo?.softwareVersion ?? '',
        cellCountReported: lastSample?.cellVoltagesV.length,
        layout: is32s ? 'JK02_32S' : 'JK02_24S',
        manufacturingYearMonth: yearMonth(deviceInfo?.manufacturingDate ?? ''),
        powerOnCountBucket: bucketPowerOnCount(deviceInfo?.powerOnCount ?? 0),
        serialHash: serialShared ? serial : null,
      ),
      advertisement: AdvertisementInfo(
        namePattern: namePattern(advertisedName),
        serviceUuids: uuids,
        rssiBucket: bucketRssi(rssi),
        addressMasked: maskMac(remoteId),
      ),
      samples: List<TelemetrySample>.unmodifiable(samples),
      settings: settingsValues == null
          ? null
          : SettingsCapture(
              values: Map<String, double>.unmodifiable(settingsValues),
              capturedAt: (settingsCapturedAt ?? captured).toUtc(),
            ),
      logbook: logbookEntries == null
          ? null
          : LogbookCapture(entries: List<LogbookCaptureEntry>.unmodifiable(logbookEntries)),
      rawFrames: frames,
      redaction: RedactionInfo(serialNumber: serialShared ? 'shared' : 'withheld'),
    );
  }

  // ---- Selection (review-before-submit, Phase 4) ---------------------------

  /// Returns a copy with the serial **shared** ([include] true and a non-empty
  /// [serial]) or withheld. The serial is never carried unless this is called
  /// with `include: true`, so it is read only when the user opts in.
  Contribution withSerial(String? serial, {required bool include}) {
    final shared = include && (serial != null && serial.trim().isNotEmpty);
    return Contribution(
      schemaVersion: schemaVersion,
      contributionId: contributionId,
      capturedAt: capturedAt,
      app: app,
      consent: consent,
      bms: BmsProvenance(
        brand: bms.brand,
        modelName: bms.modelName,
        hardwareVersion: bms.hardwareVersion,
        softwareVersion: bms.softwareVersion,
        cellCountReported: bms.cellCountReported,
        layout: bms.layout,
        manufacturingYearMonth: bms.manufacturingYearMonth,
        powerOnCountBucket: bms.powerOnCountBucket,
        serialHash: shared ? serial : null,
      ),
      advertisement: advertisement,
      samples: samples,
      settings: settings,
      logbook: logbook,
      rawFrames: rawFrames,
      redaction: RedactionInfo(
        serialNumber: shared ? 'shared' : 'withheld',
        omittedFields: redaction.omittedFields,
      ),
      sizeBytes: sizeBytes,
    );
  }

  /// Returns a copy carrying the recorded [record] (or none).
  Contribution withConsent(ConsentRecord? record) => Contribution(
        schemaVersion: schemaVersion,
        contributionId: contributionId,
        capturedAt: capturedAt,
        app: app,
        consent: record,
        bms: bms,
        advertisement: advertisement,
        samples: samples,
        settings: settings,
        logbook: logbook,
        rawFrames: rawFrames,
        redaction: redaction,
        sizeBytes: sizeBytes,
      );

  // ---- Serialisation -------------------------------------------------------

  /// Serialises the payload.
  ///
  /// When [selection] is null the full, untrimmed document is written (this is
  /// what the tests and a plain export see). When it is given, every field the
  /// user switched off is **omitted** — the key is absent, not zeroed — and
  /// which ones were withheld is recorded in `redaction.omittedFields`.
  Map<String, dynamic> toJson({ContributionSelection? selection}) {
    final fullJson = selection == null ? null : toJson();
    final omitted = fullJson == null ? const <String>[] : selection!.omittedIn(fullJson);

    final map = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'contributionId': contributionId,
      'capturedAt': utcIso(capturedAt),
      if (_include(selection, 'app')) 'app': app.toJson(),
      if (consent != null) 'consent': consent!.toJson(),
      'bms': bms.toJson(
        include: (key) => _include(selection, 'bms.$key'),
      ),
      // Advertisement has no top-level field of its own: it is carried when at
      // least one of its sub-fields is selected, and dropped when none is.
      if (_advertisementSelected(selection))
        'advertisement': advertisement.toJson(
          include: (key) => _include(selection, 'advertisement.$key'),
        ),
      if (_include(selection, 'samples'))
        'samples': samples.map((s) => s.toJson()).toList(),
      if (settings != null && _include(selection, 'settings'))
        'settings': settings!.toJson(),
      if (logbook != null && _include(selection, 'logbook'))
        'logbook': logbook!.toJson(),
      if (_include(selection, 'rawFrames'))
        'rawFrames': rawFrames.map((f) => f.toJson()).toList(),
      'redaction': RedactionInfo(
        serialNumber: redaction.serialNumber,
        omittedFields: omitted,
      ).toJson(),
    };
    // Measured before the sizeBytes field is added, so the number is not
    // self-referential.
    map['sizeBytes'] = utf8.encode(jsonEncode(map)).length;
    return map;
  }

  static bool _include(ContributionSelection? selection, String id) =>
      selection == null || selection.includes(id);

  /// Advertisement is carried when any of its sub-fields is selected (or when
  /// there is no selection at all).
  static bool _advertisementSelected(ContributionSelection? selection) {
    if (selection == null) return true;
    return const [
      'advertisement.namePattern',
      'advertisement.serviceUuids',
      'advertisement.rssiBucket',
      'advertisement.addressMasked',
    ].any(selection.includes);
  }

  /// Encodes to the wire document.
  String encode({ContributionSelection? selection}) =>
      jsonEncode(toJson(selection: selection));

  /// The exact byte length of [encode].
  int encodedBytes({ContributionSelection? selection}) =>
      utf8.encode(encode(selection: selection)).length;

  /// Whether the payload is within [maxPayloadBytes].
  bool isWithinSizeCap({ContributionSelection? selection}) =>
      encodedBytes(selection: selection) <= maxPayloadBytes;

  /// Decodes a wire document. Throws [FormatException] when a required field
  /// is missing or malformed, and [UnsupportedSchemaVersion] for an unknown
  /// major version.
  factory Contribution.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('Contribution is missing schemaVersion');
    }
    if (!isSupportedSchemaVersion(version)) {
      throw UnsupportedSchemaVersion(version);
    }

    final bms = _asMap(json['bms'], 'bms');
    final advertisement = _asMapOrEmpty(json['advertisement']);
    final app = _asMapOrEmpty(json['app']);

    return Contribution(
      schemaVersion: version,
      contributionId: _asString(json['contributionId'], 'contributionId'),
      capturedAt: _parseUtc(_asString(json['capturedAt'], 'capturedAt')),
      app: AppProvenance.fromJson(app),
      consent: json['consent'] == null
          ? null
          : ConsentRecord.fromJson(_asMap(json['consent'], 'consent')),
      bms: BmsProvenance.fromJson(bms),
      advertisement: AdvertisementInfo.fromJson(advertisement),
      samples: json['samples'] == null
          ? const []
          : _asList(json['samples'], 'samples')
              .map((e) => TelemetrySample.fromJson(_asMap(e, 'samples[]')))
              .toList(growable: false),
      settings: json['settings'] == null
          ? null
          : SettingsCapture.fromJson(_asMap(json['settings'], 'settings')),
      logbook: json['logbook'] == null
          ? null
          : LogbookCapture.fromJson(_asMap(json['logbook'], 'logbook')),
      rawFrames: json['rawFrames'] == null
          ? const []
          : _asList(json['rawFrames'], 'rawFrames')
              .map((e) => RawFrame.fromJson(_asMap(e, 'rawFrames[]')))
              .toList(growable: false),
      redaction: json['redaction'] == null
          ? const RedactionInfo(serialNumber: 'withheld')
          : RedactionInfo.fromJson(_asMap(json['redaction'], 'redaction')),
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : null,
    );
  }

  factory Contribution.decode(String source) =>
      Contribution.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// True when [version]'s major is one this client understands. Mirrors the
  /// server-side rule in plan §5 (accept the current major, reject others).
  static bool isSupportedSchemaVersion(String version) {
    final major = int.tryParse(version.split('.').first);
    return major == supportedMajorVersion;
  }

  // ---- Anonymisation helpers (pure, unit-tested) ---------------------------

  /// `YYYY-MM-DD` (or `YYYY-MM`, or `YYYY`) -> `YYYY-MM`; null when unknown or
  /// unparseable. The firmware supplies `YYMMDD`; the decoder expands it to
  /// `YYYY-MM-DD`, and only the year and month survive here.
  static String? yearMonth(String date) {
    final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(date.trim());
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}';
  }

  /// Bucketed power-on count (never the exact figure).
  static String bucketPowerOnCount(int count) {
    if (count <= 0) return '0';
    if (count < 10) return '1-9';
    if (count < 100) return '10-99';
    if (count < 1000) return '100-999';
    if (count < 10000) return '1000-9999';
    return '10000+';
  }

  /// Bucketed RSSI, in 10 dBm bands, rounded down: -65 -> `"-70..-60"`.
  static String bucketRssi(int rssi) {
    final low = (rssi / 10).floor() * 10;
    return '$low..${low + 10}';
  }

  /// Keeps the vendor OUI (first three octets) and zeroes the host part:
  /// `AA:BB:CC:11:22:33` -> `AA:BB:CC:00:00:00`. Returns null when [id] is not
  /// a MAC address (iOS delivers a per-device UUID, not a MAC — that is
  /// withheld entirely rather than sent).
  static String? maskMac(String id) {
    final normalized = id.trim().replaceAll('-', ':').toUpperCase();
    final ok = RegExp(r'^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$').hasMatch(normalized);
    if (!ok) return null;
    final octets = normalized.split(':');
    return '${octets[0]}:${octets[1]}:${octets[2]}:00:00:00';
  }

  /// A conservative, non-identifying name pattern: the first three characters
  /// plus a wildcard. The full advertised name is never carried.
  static String namePattern(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '(unnamed)';
    final prefix = trimmed.length <= 3 ? trimmed : trimmed.substring(0, 3);
    return '$prefix*';
  }

  /// Random UUIDv7 (time-ordered, RFC 9562). Never derived from the device or
  /// the user; [random] is injectable for deterministic tests.
  static String uuidV7({DateTime? now, Random? random}) {
    final rng = random ?? Random.secure();
    final ms = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final bytes = List<int>.filled(16, 0);
    bytes[0] = (ms >> 40) & 0xFF;
    bytes[1] = (ms >> 32) & 0xFF;
    bytes[2] = (ms >> 24) & 0xFF;
    bytes[3] = (ms >> 16) & 0xFF;
    bytes[4] = (ms >> 8) & 0xFF;
    bytes[5] = ms & 0xFF;
    for (int i = 6; i < 16; i++) {
      bytes[i] = rng.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x70; // version 7
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 9562 variant (10xxxxxx)
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// UTC ISO-8601 with a trailing `Z`.
  static String utcIso(DateTime dt) => dt.toUtc().toIso8601String();
}

/// Thrown when a document's `schemaVersion` major is not supported.
class UnsupportedSchemaVersion implements Exception {
  final String version;
  const UnsupportedSchemaVersion(this.version);

  @override
  String toString() =>
      'UnsupportedSchemaVersion: "$version" (this client writes '
      '${Contribution.currentSchemaVersion})';
}

/// App version + platform provenance (plan §4 `app` object).
class AppProvenance {
  final String version;
  final String platform;
  final String osVersion;

  const AppProvenance({
    required this.version,
    required this.platform,
    required this.osVersion,
  });

  Map<String, dynamic> toJson() =>
      {'version': version, 'platform': platform, 'osVersion': osVersion};

  factory AppProvenance.fromJson(Map<String, dynamic> json) => AppProvenance(
        version: json['version'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        osVersion: json['osVersion'] as String? ?? '',
      );
}

/// The user's recorded consent (Phase 4 fills this in; Phase 3 leaves it null
/// behind a clean seam).
class ConsentRecord {
  final DateTime givenAt;
  final String scope;

  const ConsentRecord({required this.givenAt, required this.scope});

  Map<String, dynamic> toJson() =>
      {'givenAt': Contribution.utcIso(givenAt), 'scope': scope};

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
        givenAt: _parseUtc(json['givenAt'] as String),
        scope: json['scope'] as String? ?? '',
      );
}

/// Device identity/provenance from the JK02 device-info frame (0x03).
///
/// [serialHash] holds the raw serial **only** when the user opted in; the
/// server stores `sha256(pepper || serial)` and discards the raw value. It is
/// null by default.
class BmsProvenance {
  final String brand;
  final String modelName;
  final String hardwareVersion;
  final String softwareVersion;
  final int? cellCountReported;
  final String layout;
  final String? manufacturingYearMonth;
  final String powerOnCountBucket;
  final String? serialHash;

  const BmsProvenance({
    required this.brand,
    required this.modelName,
    required this.hardwareVersion,
    required this.softwareVersion,
    required this.layout,
    required this.powerOnCountBucket,
    this.cellCountReported,
    this.manufacturingYearMonth,
    this.serialHash,
  });

  Map<String, dynamic> toJson({bool Function(String key)? include}) {
    bool inc(String key) => include == null || include(key);
    return {
      'brand': brand,
      if (inc('modelName')) 'modelName': modelName,
      if (inc('hardwareVersion')) 'hardwareVersion': hardwareVersion,
      if (inc('softwareVersion')) 'softwareVersion': softwareVersion,
      if (inc('cellCountReported')) 'cellCountReported': cellCountReported,
      if (inc('layout')) 'layout': layout,
      if (inc('manufacturingYearMonth'))
        'manufacturingYearMonth': manufacturingYearMonth,
      if (inc('powerOnCountBucket')) 'powerOnCountBucket': powerOnCountBucket,
      // The serial is governed by Contribution.withSerial (opt-in, default
      // withheld), not by the review selection, so it is always written here.
      'serialHash': serialHash,
    };
  }

  factory BmsProvenance.fromJson(Map<String, dynamic> json) => BmsProvenance(
        brand: json['brand'] as String? ?? 'jkbms',
        modelName: json['modelName'] as String? ?? '',
        hardwareVersion: json['hardwareVersion'] as String? ?? '',
        softwareVersion: json['softwareVersion'] as String? ?? '',
        cellCountReported: json['cellCountReported'] as int?,
        layout: json['layout'] as String? ?? 'JK02_24S',
        manufacturingYearMonth: json['manufacturingYearMonth'] as String?,
        powerOnCountBucket: json['powerOnCountBucket'] as String? ?? '0',
        serialHash: json['serialHash'] as String?,
      );
}

/// The BLE advertisement, reduced to non-identifying facts.
class AdvertisementInfo {
  final String namePattern;
  final List<String> serviceUuids;
  final String rssiBucket;
  final String? addressMasked;

  const AdvertisementInfo({
    required this.namePattern,
    required this.serviceUuids,
    required this.rssiBucket,
    this.addressMasked,
  });

  Map<String, dynamic> toJson({bool Function(String key)? include}) {
    bool inc(String key) => include == null || include(key);
    return {
      if (inc('namePattern')) 'namePattern': namePattern,
      if (inc('serviceUuids')) 'serviceUuids': serviceUuids,
      if (inc('rssiBucket')) 'rssiBucket': rssiBucket,
      if (inc('addressMasked')) 'addressMasked': addressMasked,
    };
  }

  factory AdvertisementInfo.fromJson(Map<String, dynamic> json) => AdvertisementInfo(
        namePattern: json['namePattern'] as String? ?? '(unnamed)',
        serviceUuids: (json['serviceUuids'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        rssiBucket: json['rssiBucket'] as String? ?? '',
        addressMasked: json['addressMasked'] as String?,
      );
}

/// One decoded telemetry sample, with SI units named in every field.
class TelemetrySample {
  final int tOffsetMs;
  final double voltageV;
  final double currentA;
  final double powerW;
  final int socPct;
  final double remainingCapacityAh;
  final double nominalCapacityAh;
  final int cycleCount;
  final double totalCycleCapacityAh;
  final double mosTempC;
  final double temp1C;
  final double temp2C;
  final double balanceCurrentA;
  final List<double> cellVoltagesV;
  final bool chargeMos;
  final bool dischargeMos;
  final bool balance;
  final Map<String, bool> alarms;

  const TelemetrySample({
    required this.tOffsetMs,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.socPct,
    required this.remainingCapacityAh,
    required this.nominalCapacityAh,
    required this.cycleCount,
    required this.totalCycleCapacityAh,
    required this.mosTempC,
    required this.temp1C,
    required this.temp2C,
    required this.balanceCurrentA,
    required this.cellVoltagesV,
    required this.chargeMos,
    required this.dischargeMos,
    required this.balance,
    required this.alarms,
  });

  /// Converts a decoded [BmsStatus] into a donation sample. [tOffsetMs] is
  /// measured from the start of the capture by the caller.
  factory TelemetrySample.fromStatus(BmsStatus status, {required int tOffsetMs}) {
    return TelemetrySample(
      tOffsetMs: tOffsetMs,
      voltageV: status.totalVoltage,
      currentA: status.currentA,
      powerW: status.powerW,
      socPct: status.soc,
      remainingCapacityAh: status.remainingCapacityAh,
      nominalCapacityAh: status.nominalCapacityAh,
      cycleCount: status.cycleCount,
      totalCycleCapacityAh: status.totalCycleCapacityAh,
      mosTempC: status.mosTemp,
      temp1C: status.t1Temp,
      temp2C: status.t2Temp,
      balanceCurrentA: status.balanceCurrentA,
      cellVoltagesV: status.cells.map((c) => c.voltage).toList(growable: false),
      chargeMos: status.chargeMosEnabled,
      dischargeMos: status.dischargeMosEnabled,
      balance: status.balanceEnabled,
      alarms: alarmsToJson(status.alarms),
    );
  }

  /// Fixed, allowlisted alarm map — no free-form keys can enter the payload.
  static Map<String, bool> alarmsToJson(BmsAlarms a) => {
        'cellOverVoltage': a.cellOverVoltage,
        'cellUnderVoltage': a.cellUnderVoltage,
        'batteryOverVoltage': a.batteryOverVoltage,
        'batteryUnderVoltage': a.batteryUnderVoltage,
        'chargeOverCurrent': a.chargeOverCurrent,
        'dischargeOverCurrent': a.dischargeOverCurrent,
        'chargeOverTemp': a.chargeOverTemp,
        'chargeUnderTemp': a.chargeUnderTemp,
        'dischargeOverTemp': a.dischargeOverTemp,
        'dischargeUnderTemp': a.dischargeUnderTemp,
        'mosOverTemp': a.mosOverTemp,
        'wireResistanceAnomaly': a.wireResistanceAnomaly,
        'currentSensorAnomaly': a.currentSensorAnomaly,
        'cellCountMismatch': a.cellCountMismatch,
        'fullyCharged': a.fullyCharged,
      };

  Map<String, dynamic> toJson() => {
        'tOffsetMs': tOffsetMs,
        'voltageV': voltageV,
        'currentA': currentA,
        'powerW': powerW,
        'socPct': socPct,
        'remainingCapacityAh': remainingCapacityAh,
        'nominalCapacityAh': nominalCapacityAh,
        'cycleCount': cycleCount,
        'totalCycleCapacityAh': totalCycleCapacityAh,
        'mosTempC': mosTempC,
        'temp1C': temp1C,
        'temp2C': temp2C,
        'balanceCurrentA': balanceCurrentA,
        'cellVoltagesV': cellVoltagesV,
        'chargeMos': chargeMos,
        'dischargeMos': dischargeMos,
        'balance': balance,
        'alarms': alarms,
      };

  factory TelemetrySample.fromJson(Map<String, dynamic> json) => TelemetrySample(
        tOffsetMs: (json['tOffsetMs'] as num?)?.toInt() ?? 0,
        voltageV: (json['voltageV'] as num?)?.toDouble() ?? 0,
        currentA: (json['currentA'] as num?)?.toDouble() ?? 0,
        powerW: (json['powerW'] as num?)?.toDouble() ?? 0,
        socPct: (json['socPct'] as num?)?.toInt() ?? 0,
        remainingCapacityAh: (json['remainingCapacityAh'] as num?)?.toDouble() ?? 0,
        nominalCapacityAh: (json['nominalCapacityAh'] as num?)?.toDouble() ?? 0,
        cycleCount: (json['cycleCount'] as num?)?.toInt() ?? 0,
        totalCycleCapacityAh: (json['totalCycleCapacityAh'] as num?)?.toDouble() ?? 0,
        mosTempC: (json['mosTempC'] as num?)?.toDouble() ?? 0,
        temp1C: (json['temp1C'] as num?)?.toDouble() ?? 0,
        temp2C: (json['temp2C'] as num?)?.toDouble() ?? 0,
        balanceCurrentA: (json['balanceCurrentA'] as num?)?.toDouble() ?? 0,
        cellVoltagesV: (json['cellVoltagesV'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(growable: false),
        chargeMos: json['chargeMos'] as bool? ?? false,
        dischargeMos: json['dischargeMos'] as bool? ?? false,
        balance: json['balance'] as bool? ?? false,
        alarms: (json['alarms'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, v as bool? ?? false)),
      );
}

/// A captured settings dump (best-effort; null when none was read).
class SettingsCapture {
  final Map<String, double> values;
  final DateTime capturedAt;

  const SettingsCapture({required this.values, required this.capturedAt});

  Map<String, dynamic> toJson() =>
      {'values': values, 'capturedAt': Contribution.utcIso(capturedAt)};

  factory SettingsCapture.fromJson(Map<String, dynamic> json) => SettingsCapture(
        values: (json['values'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        capturedAt: _parseUtc(json['capturedAt'] as String? ?? ''),
      );
}

/// A captured on-board logbook (best-effort; null when none was read).
class LogbookCapture {
  final List<LogbookCaptureEntry> entries;

  const LogbookCapture({required this.entries});

  Map<String, dynamic> toJson() =>
      {'entries': entries.map((e) => e.toJson()).toList()};

  factory LogbookCapture.fromJson(Map<String, dynamic> json) => LogbookCapture(
        entries: (json['entries'] as List<dynamic>? ?? const [])
            .map((e) => LogbookCaptureEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class LogbookCaptureEntry {
  final int seconds;
  final int code;

  const LogbookCaptureEntry({required this.seconds, required this.code});

  Map<String, dynamic> toJson() => {'seconds': seconds, 'code': code};

  factory LogbookCaptureEntry.fromJson(Map<String, dynamic> json) =>
      LogbookCaptureEntry(
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        code: (json['code'] as num?)?.toInt() ?? 0,
      );
}

/// One raw frame exactly as it crossed the wire.
class RawFrame {
  final String dir;
  final int tOffsetMs;
  final String hex;
  final String frameType;

  const RawFrame({
    required this.dir,
    required this.tOffsetMs,
    required this.hex,
    required this.frameType,
  });

  Map<String, dynamic> toJson() =>
      {'dir': dir, 'tOffsetMs': tOffsetMs, 'hex': hex, 'frameType': frameType};

  factory RawFrame.fromJson(Map<String, dynamic> json) => RawFrame(
        dir: json['dir'] as String? ?? 'rx',
        tOffsetMs: (json['tOffsetMs'] as num?)?.toInt() ?? 0,
        hex: json['hex'] as String? ?? '',
        frameType: json['frameType'] as String? ?? 'unknown',
      );
}

/// Records what the user withheld, so downstream analysis can tell
/// "absent" from "zero".
class RedactionInfo {
  final String serialNumber;

  /// Field ids the user switched off on the review screen, when they held a
  /// value. Empty on a full (untrimmed) payload.
  final List<String> omittedFields;

  const RedactionInfo({
    this.serialNumber = 'withheld',
    this.omittedFields = const [],
  });

  Map<String, dynamic> toJson() => {
        'serialNumber': serialNumber,
        if (omittedFields.isNotEmpty) 'omittedFields': omittedFields,
      };

  factory RedactionInfo.fromJson(Map<String, dynamic> json) => RedactionInfo(
        serialNumber: json['serialNumber'] as String? ?? 'withheld',
        omittedFields: (json['omittedFields'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
      );
}

// ---- small JSON helpers ----------------------------------------------------

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Contribution field "$field" must be an object');
}

/// A section that is optional in a trimmed payload: absent reads as empty.
Map<String, dynamic> _asMapOrEmpty(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<dynamic> _asList(Object? value, String field) {
  if (value is List) return value;
  throw FormatException('Contribution field "$field" must be an array');
}

String _asString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('Contribution field "$field" must be a string');
}

DateTime _parseUtc(String iso) => DateTime.parse(iso).toUtc();
