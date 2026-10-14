/// Per-field control over what a contribution actually carries.
///
/// The schema in `contribution.dart` is deliberately an allowlist: the only
/// things that can be serialised are the fields it names, and their defaults
/// are the redacted ones. This file adds the *user's* layer on top of that —
/// the review screen (plan §3.4) lets someone switch off any field, and the
/// serialiser omits exactly the fields switched off.
///
/// Granularity is one entry per meaningful field or collection, so a checkbox
/// maps to something in the payload rather than to a vague "device info"
/// bucket. Bluetooth identity is per-field too (name pattern, service UUIDs,
/// signal bucket, masked address), because those are the fields most likely to
/// be recognisable.
///
/// [ContributionFields.all] excludes the serial number on purpose: the serial
/// is an **opt-in** (default withheld) rather than an opt-out, and it is
/// handled by `Contribution.withSerial` so the value is only ever read when the
/// user asks for it.
library;

/// One selectable field (or field group) on the review screen.
class ContributionField {
  /// Stable identifier. Also the payload path for scalar fields, e.g.
  /// `bms.modelName` or `advertisement.rssiBucket`; a bare section name for a
  /// field that is a whole collection, e.g. `samples`.
  final String id;

  /// Presentation group heading.
  final String group;

  /// Short human label.
  final String label;

  /// One line explaining what the field is, shown under the label.
  final String description;

  /// Whether it is selected when the review screen opens. Every field here is
  /// on by default; only the serial is off (and it is not a
  /// [ContributionField]).
  final bool defaultIncluded;

  /// Top-level payload object this field lives in (`bms`, `advertisement`,
  /// `app`), or null when [id] is itself a top-level section.
  final String? topLevel;

  /// Key inside [topLevel], or null when the field *is* the section.
  final String? key;

  const ContributionField({
    required this.id,
    required this.group,
    required this.label,
    required this.description,
    this.defaultIncluded = true,
    this.topLevel,
    this.key,
  });

  /// The value this field would carry in [json], or null when absent. Used to
  /// show the current value beside the checkbox and to tell "the user withheld
  /// this" from "there was nothing to withhold".
  Object? valueFrom(Map<String, dynamic> json) {
    if (topLevel == null) return null;
    final section = json[topLevel];
    if (key == null) return section;
    if (section is Map<String, dynamic>) return section[key];
    return null;
  }

  /// Whether [json] actually carries a value for this field.
  bool isPresentIn(Map<String, dynamic> json) => _hasValue(valueFrom(json));

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return true;
    if (value is bool) return true;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}

/// The registry of selectable fields, in display order.
abstract final class ContributionFields {
  static const List<ContributionField> all = [
    ContributionField(
      id: 'bms.modelName',
      group: 'Device',
      label: 'Model name',
      description: "The BMS model reported in the device-info frame.",
      topLevel: 'bms',
      key: 'modelName',
    ),
    ContributionField(
      id: 'bms.hardwareVersion',
      group: 'Device',
      label: 'Hardware version',
      description: 'The board revision string (e.g. 11.X).',
      topLevel: 'bms',
      key: 'hardwareVersion',
    ),
    ContributionField(
      id: 'bms.softwareVersion',
      group: 'Device',
      label: 'Firmware version',
      description: 'The BMS firmware string (e.g. 11.30).',
      topLevel: 'bms',
      key: 'softwareVersion',
    ),
    ContributionField(
      id: 'bms.cellCountReported',
      group: 'Device',
      label: 'Cell count',
      description: 'How many cells the pack reports.',
      topLevel: 'bms',
      key: 'cellCountReported',
    ),
    ContributionField(
      id: 'bms.layout',
      group: 'Device',
      label: 'Cell layout',
      description: 'The register layout in use (24S or 32S).',
      topLevel: 'bms',
      key: 'layout',
    ),
    ContributionField(
      id: 'bms.manufacturingYearMonth',
      group: 'Device',
      label: 'Manufacturing month',
      description: 'Year and month only — never the day.',
      topLevel: 'bms',
      key: 'manufacturingYearMonth',
    ),
    ContributionField(
      id: 'bms.powerOnCountBucket',
      group: 'Device',
      label: 'Power-on count',
      description: 'A range, never the exact figure.',
      topLevel: 'bms',
      key: 'powerOnCountBucket',
    ),
    ContributionField(
      id: 'advertisement.namePattern',
      group: 'Bluetooth',
      label: 'Advertised name',
      description: 'The first three characters and a wildcard.',
      topLevel: 'advertisement',
      key: 'namePattern',
    ),
    ContributionField(
      id: 'advertisement.serviceUuids',
      group: 'Bluetooth',
      label: 'Service UUIDs',
      description: 'The BLE profiles the device advertises.',
      topLevel: 'advertisement',
      key: 'serviceUuids',
    ),
    ContributionField(
      id: 'advertisement.rssiBucket',
      group: 'Bluetooth',
      label: 'Signal strength',
      description: 'A 10 dBm band, not a raw reading.',
      topLevel: 'advertisement',
      key: 'rssiBucket',
    ),
    ContributionField(
      id: 'advertisement.addressMasked',
      group: 'Bluetooth',
      label: 'Address prefix',
      description: 'The vendor prefix; the device-specific part is zeroed.',
      topLevel: 'advertisement',
      key: 'addressMasked',
    ),
    ContributionField(
      id: 'samples',
      group: 'Telemetry',
      label: 'Telemetry samples',
      description: 'Decoded voltage, current, temperature, SOC and alarms.',
      topLevel: 'samples',
    ),
    ContributionField(
      id: 'settings',
      group: 'Settings & logbook',
      label: 'Settings snapshot',
      description: 'The BMS parameter values read during capture.',
      topLevel: 'settings',
    ),
    ContributionField(
      id: 'logbook',
      group: 'Settings & logbook',
      label: 'Logbook entries',
      description: "The battery's on-board event log.",
      topLevel: 'logbook',
    ),
    ContributionField(
      id: 'rawFrames',
      group: 'Raw data',
      label: 'Raw JK02 frames',
      description: 'The exact bytes from the BMS, as hex.',
      topLevel: 'rawFrames',
    ),
    ContributionField(
      id: 'app',
      group: 'App',
      label: 'App & OS version',
      description: 'The app build and OS version, not the phone model.',
      topLevel: 'app',
    ),
  ];

  /// Fields selected when the review screen opens.
  static List<ContributionField> defaults() =>
      all.where((f) => f.defaultIncluded).toList(growable: false);
}

/// The set of field ids a user has left switched on.
class ContributionSelection {
  final Set<String> _included;

  ContributionSelection(Iterable<String> included)
      : _included = Set<String>.unmodifiable(included);

  /// Everything on (privacy-first defaults), except fields that default off.
  factory ContributionSelection.defaults() =>
      ContributionSelection(ContributionFields.defaults().map((f) => f.id));

  /// Nothing on.
  factory ContributionSelection.none() => ContributionSelection(const []);

  bool includes(String id) => _included.contains(id);

  Set<String> get ids => _included;

  /// Returns a copy with [id] switched to [included].
  ContributionSelection toggled(String id, bool included) {
    final next = Set<String>.of(_included);
    if (included) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return ContributionSelection(next);
  }

  /// The switched-off fields that actually held a value in [fullJson].
  ///
  /// This is what makes the payload's `redaction.omittedFields` honest: it
  /// lists what the user withheld, not merely everything they did not tick,
  /// so downstream analysis can tell "withheld" from "there was nothing".
  List<String> omittedIn(Map<String, dynamic> fullJson) => [
        for (final field in ContributionFields.all)
          if (!includes(field.id) && field.isPresentIn(fullJson)) field.id,
      ];
}
