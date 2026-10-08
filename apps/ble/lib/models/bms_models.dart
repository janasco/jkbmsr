enum BmsBrand {
  jkbms,
  daly,
  jbd,
  ant,
  seplos,
  tianpower,
  basen,
  ks,
  ogt,
  topband,
  lolan,
  unknown,
}

/// Whether a brand is a publicly supported JKBMSR product target or an
/// internal protocol implementation.
///
/// JKBMSR publicly supports **JK-BMS only**. Every other decoder is retained
/// because it is load-bearing engineering work, not because it is a support
/// claim:
///
///  * The multi-brand candidate set is what makes service-UUID collision
///    ranking reliable for JK-BMS itself (0xFFE0 and 0xFF00 are both shared),
///    so [isPublic] must never be used to filter detection candidates.
///  * A device from an internal brand must stay labelled as *itself* so the
///    app does not write JK02 frames to a non-JK pack.
///
/// Presentation and copy are gated on this flag; detection and the
/// capability matrix are not.
extension BmsBrandVisibility on BmsBrand {
  bool get isPublic => this == BmsBrand.jkbms;
}

/// Which switches/controls this app can actually send to a given BMS brand.
/// Scoped to what has a documented, verifiable BLE/UART write protocol —
/// brands without one are monitoring-only rather than guessing at command
/// bytes against real battery hardware.
class BmsCapabilities {
  final bool canToggleCharge;
  final bool canToggleDischarge;
  final bool canToggleBalance;
  final bool hasExtendedJkSwitches; // emergency/tempSensor/display/etc.
  final bool hasTimeCalibration;

  const BmsCapabilities({
    this.canToggleCharge = false,
    this.canToggleDischarge = false,
    this.canToggleBalance = false,
    this.hasExtendedJkSwitches = false,
    this.hasTimeCalibration = false,
  });

  bool get hasAnyControl => canToggleCharge || canToggleDischarge || canToggleBalance;

  static BmsCapabilities forBrand(BmsBrand brand) {
    switch (brand) {
      case BmsBrand.jkbms:
        // Charge/discharge/balance are read from and written to real JK02
        // registers (0x1D/0x1E/0x1F) and confirmed against live hardware.
        // The extended switches (emergency, temp sensor bypass, display,
        // smart sleep, timed data, float mode, dry arm, OCP levels) and
        // time calibration are deliberately NOT exposed here: this app has
        // no way to read their real current state from hardware — the
        // JK02 Settings frame (0x01) that would report them isn't decoded
        // — so showing them would mean displaying fabricated on/off state
        // next to a real toggle switch. Re-enable once Settings-frame
        // decoding lands.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
          canToggleBalance: true,
        );
      case BmsBrand.daly:
        // Verified against syssi/esphome-daly-bms: independent charge
        // (0xA5), discharge (0xA6), and balancer (0xCF) holding-register
        // writes over the D2/Modbus BLE protocol.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
          canToggleBalance: true,
        );
      case BmsBrand.jbd:
        // JBD/Xiaoxiang's 0xE1 MOS control register toggles charge and
        // discharge MOSFETs (as a combined bitmask). A balancer register
        // exists (0x2D) but upstream (syssi/esphome-jbd-bms) deliberately
        // leaves it disabled/unexposed — matching that here rather than
        // exposing an unverified control.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
        );
      case BmsBrand.ant:
        // Verified against syssi/esphome-ant-bms: charge/discharge/
        // balancer are each a pair of turn-on/turn-off register writes.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
          canToggleBalance: true,
        );
      case BmsBrand.seplos:
        // Verified against syssi/esphome-seplos-bms: charge/discharge are
        // bits in a single MOSFET-control command (function 0xAA). That
        // command also covers current-limit/heating switches this app
        // doesn't model yet, and there's no separate balancer bit.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
        );
      case BmsBrand.basen:
        // Verified against syssi/esphome-basen-bms: charge and discharge
        // are two bits (0/1) of the same holding register (0x011D).
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
        );
      case BmsBrand.ks:
        // Verified against syssi/esphome-ks-bms: independent charge
        // (0x1D) and discharge (0x1E) holding-register writes.
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
        );
      case BmsBrand.lolan:
        // Verified against syssi/esphome-lolan-bms: distinct turn-on/
        // turn-off command codes per switch (not a register+value write).
        return const BmsCapabilities(
          canToggleCharge: true,
          canToggleDischarge: true,
        );
      case BmsBrand.tianpower:
      case BmsBrand.topband:
        // Monitoring-only components upstream — no switch/control
        // support exists in syssi/esphome-tianpower-bms or
        // esphome-topband-bms.
        return const BmsCapabilities();
      case BmsBrand.ogt:
        // esphome-ogt-bms requires a per-device encryption key and
        // device sub-type (A/B) with no sane default — this app has no
        // way to obtain those automatically, so Offgridtec is detected
        // by name but left unimplemented rather than guessed.
        return const BmsCapabilities();
      case BmsBrand.unknown:
        return const BmsCapabilities();
    }
  }
}

enum ConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

enum ChargeState {
  charging,
  discharging,
  idle,
}

class CellInfo {
  final int index;
  final double voltage; // in Volts
  final double wireResistance; // in Ohms
  final bool isBalancing;

  const CellInfo({
    required this.index,
    required this.voltage,
    this.wireResistance = 0.0012,
    this.isBalancing = false,
  });

  double get resistanceMOhms => (wireResistance * 1000).clamp(0.1, 99.9);
}

class DiagnosticFrame {
  final String timestamp;
  final String frameType;
  final String frameHex;
  final String status;

  const DiagnosticFrame({
    required this.timestamp,
    required this.frameType,
    required this.frameHex,
    required this.status,
  });
}

class BmsAlarms {
  final bool cellOverVoltage;
  final bool cellUnderVoltage;
  final bool batteryOverVoltage;
  final bool batteryUnderVoltage;
  final bool chargeOverCurrent;
  final bool dischargeOverCurrent;
  final bool chargeOverTemp;
  final bool chargeUnderTemp;
  final bool dischargeOverTemp;
  final bool dischargeUnderTemp;
  final bool mosOverTemp;
  final bool wireResistanceAnomaly;
  final bool currentSensorAnomaly;
  final bool cellCountMismatch;
  final bool fullyCharged;

  const BmsAlarms({
    this.cellOverVoltage = false,
    this.cellUnderVoltage = false,
    this.batteryOverVoltage = false,
    this.batteryUnderVoltage = false,
    this.chargeOverCurrent = false,
    this.dischargeOverCurrent = false,
    this.chargeOverTemp = false,
    this.chargeUnderTemp = false,
    this.dischargeOverTemp = false,
    this.dischargeUnderTemp = false,
    this.mosOverTemp = false,
    this.wireResistanceAnomaly = false,
    this.currentSensorAnomaly = false,
    this.cellCountMismatch = false,
    this.fullyCharged = false,
  });

  bool get hasActiveAlarms =>
      cellOverVoltage ||
      cellUnderVoltage ||
      batteryOverVoltage ||
      batteryUnderVoltage ||
      chargeOverCurrent ||
      dischargeOverCurrent ||
      chargeOverTemp ||
      chargeUnderTemp ||
      dischargeOverTemp ||
      dischargeUnderTemp ||
      mosOverTemp ||
      wireResistanceAnomaly ||
      currentSensorAnomaly ||
      cellCountMismatch;

  List<String> get activeAlarmList {
    final list = <String>[];
    if (cellOverVoltage) list.add('Cell Over Voltage');
    if (cellUnderVoltage) list.add('Cell Under Voltage');
    if (batteryOverVoltage) list.add('Battery Over Voltage');
    if (batteryUnderVoltage) list.add('Battery Under Voltage');
    if (chargeOverCurrent) list.add('Charge Over Current');
    if (dischargeOverCurrent) list.add('Discharge Over Current');
    if (chargeOverTemp) list.add('Charge Over Temp.');
    if (chargeUnderTemp) list.add('Charge Under Temp.');
    if (dischargeOverTemp) list.add('Discharge Over Temp.');
    if (dischargeUnderTemp) list.add('Discharge Under Temp.');
    if (mosOverTemp) list.add('MOS Over Temp.');
    if (wireResistanceAnomaly) list.add('Sample-wire Resistance Too Large');
    if (currentSensorAnomaly) list.add('Current Sensor Anomaly');
    if (cellCountMismatch) list.add('Cell Count is Not Equal to Settings');
    if (fullyCharged) list.add('Battery is Fully Charged');
    return list;
  }
}

class BmsStatus {
  final BmsBrand brand;
  final String modelName;
  final int soc; // 0 - 100%
  final double totalVoltage; // V
  final double currentA; // A (positive = charge, negative = discharge)
  final double powerW; // W
  final double remainingCapacityAh; // Ah
  final double nominalCapacityAh; // Ah
  final int cycleCount;
  final double totalCycleCapacityAh;
  final List<CellInfo> cells;
  final double mosTemp; // °C
  final double t1Temp; // °C
  final double t2Temp; // °C
  final double balanceCurrentA; // A
  final String cellType;
  final int timeEnterSleepSec;

  // Switches
  final bool chargeMosEnabled;
  final bool dischargeMosEnabled;
  final bool balanceEnabled;

  final BmsAlarms alarms;
  final DateTime timestamp;

  const BmsStatus({
    this.brand = BmsBrand.jkbms,
    this.modelName = 'JK_B1A24S_P',
    this.soc = 85,
    this.totalVoltage = 53.40,
    this.currentA = -5.40,
    this.powerW = 288.36,
    this.remainingCapacityAh = 238.0,
    this.nominalCapacityAh = 280.0,
    this.cycleCount = 42,
    this.totalCycleCapacityAh = 11760.0,
    this.cells = const [],
    this.mosTemp = 38.5,
    this.t1Temp = 32.4,
    this.t2Temp = 33.0,
    this.balanceCurrentA = 0.8,
    this.cellType = 'LiFePO4',
    this.timeEnterSleepSec = 3600,
    this.chargeMosEnabled = true,
    this.dischargeMosEnabled = true,
    this.balanceEnabled = true,
    this.alarms = const BmsAlarms(),
    required this.timestamp,
  });

  /// Returns a copy with the given fields replaced, defaulting to this
  /// status's own values — used to merge a brand's separately-arriving
  /// frames (e.g. a status frame plus a later cell-voltage frame) into one
  /// up-to-date [BmsStatus] instead of overwriting already-known fields.
  BmsStatus copyWith({
    BmsBrand? brand,
    String? modelName,
    int? soc,
    double? totalVoltage,
    double? currentA,
    double? powerW,
    double? remainingCapacityAh,
    double? nominalCapacityAh,
    int? cycleCount,
    double? totalCycleCapacityAh,
    List<CellInfo>? cells,
    double? mosTemp,
    double? t1Temp,
    double? t2Temp,
    double? balanceCurrentA,
    bool? chargeMosEnabled,
    bool? dischargeMosEnabled,
    bool? balanceEnabled,
  }) {
    return BmsStatus(
      brand: brand ?? this.brand,
      modelName: modelName ?? this.modelName,
      soc: soc ?? this.soc,
      totalVoltage: totalVoltage ?? this.totalVoltage,
      currentA: currentA ?? this.currentA,
      powerW: powerW ?? this.powerW,
      remainingCapacityAh: remainingCapacityAh ?? this.remainingCapacityAh,
      nominalCapacityAh: nominalCapacityAh ?? this.nominalCapacityAh,
      cycleCount: cycleCount ?? this.cycleCount,
      totalCycleCapacityAh: totalCycleCapacityAh ?? this.totalCycleCapacityAh,
      cells: cells ?? this.cells,
      mosTemp: mosTemp ?? this.mosTemp,
      t1Temp: t1Temp ?? this.t1Temp,
      t2Temp: t2Temp ?? this.t2Temp,
      balanceCurrentA: balanceCurrentA ?? this.balanceCurrentA,
      cellType: cellType,
      timeEnterSleepSec: timeEnterSleepSec,
      chargeMosEnabled: chargeMosEnabled ?? this.chargeMosEnabled,
      dischargeMosEnabled: dischargeMosEnabled ?? this.dischargeMosEnabled,
      balanceEnabled: balanceEnabled ?? this.balanceEnabled,
      alarms: alarms,
      timestamp: DateTime.now(),
    );
  }

  ChargeState get chargeState {
    if (currentA > 0.15) return ChargeState.charging;
    if (currentA < -0.15) return ChargeState.discharging;
    return ChargeState.idle;
  }

  double get minCellVoltage =>
      cells.isEmpty ? 0.0 : cells.map((c) => c.voltage).reduce((a, b) => a < b ? a : b);

  double get maxCellVoltage =>
      cells.isEmpty ? 0.0 : cells.map((c) => c.voltage).reduce((a, b) => a > b ? a : b);

  int get maxCellIndex {
    if (cells.isEmpty) return 0;
    int maxIdx = 0;
    for (int i = 1; i < cells.length; i++) {
      if (cells[i].voltage > cells[maxIdx].voltage) maxIdx = i;
    }
    return maxIdx;
  }

  int get minCellIndex {
    if (cells.isEmpty) return 0;
    int minIdx = 0;
    for (int i = 1; i < cells.length; i++) {
      if (cells[i].voltage < cells[minIdx].voltage) minIdx = i;
    }
    return minIdx;
  }

  double get deltaCellVoltage => maxCellVoltage - minCellVoltage;
  int get deltaCellVoltageMv => (deltaCellVoltage * 1000).round();
  int get deltaVoltageMv => deltaCellVoltageMv;

  double get averageCellVoltage =>
      cells.isEmpty ? 0.0 : cells.map((c) => c.voltage).reduce((a, b) => a + b) / cells.length;

  double get current => currentA;
  double get power => powerW;
  double get remainCapacityAh => remainingCapacityAh;
  double get tempMos => mosTemp;
  double get tempT1 => t1Temp;
  double get tempT2 => t2Temp;
  double get balanceCurrent => balanceCurrentA;
  bool get isBalancingActive => balanceEnabled && (balanceCurrentA > 0.05 || cells.any((c) => c.isBalancing));
}

/// One event recorded in the BMS's own on-board logbook (JK02 frame type
/// 0x05). Decoded from a real captured frame; see [Jk02Logbook].
class Jk02LogbookEntry {
  /// Event code exactly as sent on the wire (the final byte of the 5-byte
  /// entry).
  final int code;

  /// Human-readable name for [code] from syssi/esphome-jk-bms's
  /// `LOGBOOK_CODES` table. Empty when the code is not a documented event.
  final String name;

  /// The entry's timestamp value in seconds. The BMS does not send an
  /// absolute wall-clock time — syssi formats this same value as
  /// `DdHHhMMmSSs`, so it is exposed as a relative elapsed offset rather
  /// than being misrepresented as a calendar date.
  final int seconds;

  const Jk02LogbookEntry({
    required this.code,
    required this.name,
    required this.seconds,
  });
}

/// The BMS's on-board event log ("logbook"), decoded from a JK02 logbook
/// frame (type 0x05). This is genuine BMS-side history, not app-side
/// accumulation: it is requested from the hardware with command `0xA1`
/// (syssi's `retrieve_logbook` button) and answered with frame type 0x05.
class Jk02Logbook {
  /// Number of log entries the BMS reports at frame offset 6 (u32 LE).
  final int logCount;

  /// Decoded entries in the order the BMS sent them.
  final List<Jk02LogbookEntry> entries;

  final DateTime timestamp;

  const Jk02Logbook({
    required this.logCount,
    required this.entries,
    required this.timestamp,
  });
}

class BleDeviceInfo {
  final String id;
  final String name;
  final int rssi;
  final BmsBrand brand;
  final bool isConnectable;
  /// True if the device advertises a known BMS GATT service UUID even
  /// though its name didn't match a recognized brand pattern — a hint
  /// this might still be a BMS (e.g. a renamed or blank-name module).
  final bool looksLikeBms;
  /// Advertised GATT service UUIDs (lower-cased). Used by DetectionEngine
  /// to rank plausible brands beyond the name-only guess.
  final Set<String> serviceUuids;

  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
    required this.brand,
    this.isConnectable = true,
    this.looksLikeBms = false,
    this.serviceUuids = const {},
  });
}
