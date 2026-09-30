/// Represents individual cell voltage data inside battery pack telemetry.
class CellVoltage {
  final int cell;
  final double voltage;

  CellVoltage({required this.cell, required this.voltage});

  factory CellVoltage.fromJson(Map<String, dynamic> json) {
    return CellVoltage(
      cell: json['cell'] as int? ?? 0,
      voltage: (json['voltage'] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cell': cell,
      'voltage': voltage,
    };
  }
}

/// Extended JK-BMS fields the gateway uploads on every telemetry POST.
/// Maps exactly to the API's `bms` object (`parseBmsExtras` in
/// `jkbmsr-api/src/routes/dashboard.ts`) — kept separate from the generic
/// `diagnostics` bag (BLE/OTA link status), which is a different object.
class BmsExtras {
  final double mosfetTemperature;
  final double minCellVoltage;
  final double maxCellVoltage;
  final double avgCellVoltage;
  final double deltaCellVoltage;
  final int minVoltageCell;
  final int maxVoltageCell;
  final int cycleCount;
  final double cycleCapacityAh;
  final double fullCapacityAh;
  final double remainingCapacityAh;
  // Null when the transport (typically UART) can't report it, rather than a
  // sentinel value — the firmware omits the key entirely in that case.
  final double? stateOfHealth;
  final double balancingCurrent;
  final bool balancing;
  final bool charging;
  final bool discharging;
  final int errorsBitmask;

  BmsExtras({
    required this.mosfetTemperature,
    required this.minCellVoltage,
    required this.maxCellVoltage,
    required this.avgCellVoltage,
    required this.deltaCellVoltage,
    required this.minVoltageCell,
    required this.maxVoltageCell,
    required this.cycleCount,
    required this.cycleCapacityAh,
    required this.fullCapacityAh,
    required this.remainingCapacityAh,
    required this.stateOfHealth,
    required this.balancingCurrent,
    required this.balancing,
    required this.charging,
    required this.discharging,
    required this.errorsBitmask,
  });

  factory BmsExtras.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    return BmsExtras(
      mosfetTemperature: (data['mosfetTemperature'] as num? ?? 0).toDouble(),
      minCellVoltage: (data['minCellVoltage'] as num? ?? 0).toDouble(),
      maxCellVoltage: (data['maxCellVoltage'] as num? ?? 0).toDouble(),
      avgCellVoltage: (data['avgCellVoltage'] as num? ?? 0).toDouble(),
      deltaCellVoltage: (data['deltaCellVoltage'] as num? ?? 0).toDouble(),
      minVoltageCell: (data['minVoltageCell'] as num? ?? 0).toInt(),
      maxVoltageCell: (data['maxVoltageCell'] as num? ?? 0).toInt(),
      cycleCount: (data['cycleCount'] as num? ?? 0).toInt(),
      cycleCapacityAh: (data['cycleCapacityAh'] as num? ?? 0).toDouble(),
      fullCapacityAh: (data['fullCapacityAh'] as num? ?? 0).toDouble(),
      remainingCapacityAh: (data['remainingCapacityAh'] as num? ?? 0).toDouble(),
      stateOfHealth: (data['stateOfHealth'] as num?)?.toDouble(),
      balancingCurrent: (data['balancingCurrent'] as num? ?? 0).toDouble(),
      balancing: data['balancing'] == true,
      charging: data['charging'] == true,
      discharging: data['discharging'] == true,
      errorsBitmask: (data['errorsBitmask'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mosfetTemperature': mosfetTemperature,
      'minCellVoltage': minCellVoltage,
      'maxCellVoltage': maxCellVoltage,
      'avgCellVoltage': avgCellVoltage,
      'deltaCellVoltage': deltaCellVoltage,
      'minVoltageCell': minVoltageCell,
      'maxVoltageCell': maxVoltageCell,
      'cycleCount': cycleCount,
      'cycleCapacityAh': cycleCapacityAh,
      'fullCapacityAh': fullCapacityAh,
      'remainingCapacityAh': remainingCapacityAh,
      'stateOfHealth': stateOfHealth,
      'balancingCurrent': balancingCurrent,
      'balancing': balancing,
      'charging': charging,
      'discharging': discharging,
      'errorsBitmask': errorsBitmask,
    };
  }
}

/// Whether the gateway currently has a working link to the battery, plus the
/// BLE details that explain a broken one. This is read out of the `diagnostics`
/// object the API already returns from the latest telemetry payload — the
/// gateway uploads `bmsLinkUp` / `parser` / `ble` in every telemetry POST
/// (`parseDiagnostics` in jkbmsr-api/src/routes/dashboard.ts), but the dashboard
/// never surfaced them, so a gateway that was online with a dead BMS link looked
/// like an empty battery with no explanation.
class BmsLinkDiagnostics {
  /// Null means "the payload did not say", which is deliberately distinct from
  /// false: older firmware, or a gateway with no telemetry row yet, must not be
  /// reported as a down link.
  final bool? bmsLinkUp;

  /// Raw firmware BLE state, e.g. "connected", "connection_failed", "scanning".
  final String bleState;

  /// Last BLE error the gateway recorded; empty when there is none.
  final String lastError;

  /// BLE RSSI in dBm, or -128 when the gateway did not report one.
  final int rssi;

  /// Bytes the JK-BMS parser has received; 0 with a down link is expected.
  final int bytesReceived;

  const BmsLinkDiagnostics({
    required this.bmsLinkUp,
    required this.bleState,
    required this.lastError,
    required this.rssi,
    required this.bytesReceived,
  });

  factory BmsLinkDiagnostics.fromDiagnostics(Map<String, dynamic> diagnostics) {
    final bleValue = diagnostics['ble'];
    final ble = bleValue is Map ? bleValue : const <dynamic, dynamic>{};
    final rssi = ble['rssi'];
    final bytesReceived = diagnostics['bytesReceived'];
    return BmsLinkDiagnostics(
      bmsLinkUp: diagnostics['bmsLinkUp'] is bool ? diagnostics['bmsLinkUp'] as bool : null,
      bleState: ble['state'] is String ? ble['state'] as String : '',
      lastError: ble['lastError'] is String ? ble['lastError'] as String : '',
      rssi: rssi is num ? rssi.toInt() : -128,
      bytesReceived: bytesReceived is num ? bytesReceived.toInt() : 0,
    );
  }

  /// True only when the gateway explicitly reported the link down. An absent
  /// field stays "unknown" and must not raise the banner.
  bool get isDown => bmsLinkUp == false;
}

/// Represents real-time battery diagnostics and telemetry data.
/// Maps exactly to the `/api/v1/dashboard/devices/:deviceId` response schema.
class Telemetry {
  final double voltage;
  final double current;
  final double power;
  final double soc;
  final double temperature1;
  final double temperature2;
  final List<CellVoltage> cells;
  final BmsExtras bms;
  final Map<String, dynamic> diagnostics;

  Telemetry({
    required this.voltage,
    required this.current,
    required this.power,
    required this.soc,
    required this.temperature1,
    required this.temperature2,
    required this.cells,
    required this.bms,
    required this.diagnostics,
  });

  /// BMS-link health parsed out of [diagnostics]; see [BmsLinkDiagnostics].
  BmsLinkDiagnostics get linkDiagnostics => BmsLinkDiagnostics.fromDiagnostics(diagnostics);

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    final cellsList = json['cells'] as List<dynamic>? ?? [];
    return Telemetry(
      voltage: (json['voltage'] as num? ?? 0).toDouble(),
      current: (json['current'] as num? ?? 0).toDouble(),
      power: (json['power'] as num? ?? 0).toDouble(),
      soc: (json['soc'] as num? ?? 0).toDouble(),
      temperature1: (json['temperature1'] as num? ?? 0).toDouble(),
      temperature2: (json['temperature2'] as num? ?? 0).toDouble(),
      cells: cellsList
          .map((item) => CellVoltage.fromJson(item as Map<String, dynamic>))
          .toList(),
      bms: BmsExtras.fromJson(json['bms'] as Map<String, dynamic>?),
      diagnostics: json['diagnostics'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'voltage': voltage,
      'current': current,
      'power': power,
      'soc': soc,
      'temperature1': temperature1,
      'temperature2': temperature2,
      'cells': cells.map((c) => c.toJson()).toList(),
      'bms': bms.toJson(),
      'diagnostics': diagnostics,
    };
  }
}
