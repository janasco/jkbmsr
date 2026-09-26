import 'bms_models.dart';

/// How a single BMS configuration value is edited.
enum BmsParameterType {
  /// Numeric value with a unit (voltage, current, temperature, capacity...).
  number,

  /// On/Off switch (0.0 / 1.0 in [BmsSettingsSnapshot.values]).
  toggle,

  /// Enum-style picker; [BmsParameter.options] carries the labels and the
  /// stored value is the selected option's index.
  choice,
}

/// One configurable setting of a BMS, statically described.
///
/// A parameter binds to exactly one protocol family (JK02 settings frame,
/// Daly holding register, or KS config frame). Only the fields of the
/// matching protocol are populated; the rest stay null/default so a
/// [BmsParameter] can never accidentally be written to the wrong protocol
/// family. All offsets/registers/factors below were taken byte-for-byte
/// from the corresponding `syssi/esphome-*-bms` component source:
///
///  * JK02  — `decode_jk02_settings_` (read offsets 6..138) and
///    `number/__init__.py` NUMBERS table (write registers + factors).
///  * Daly  — `number/__init__.py` NUMBERS table (register, factor,
///    offset, range) and `decode_settings_data_` (`(raw-offset)/factor`).
///  * KS    — `number/__init__.py` NUMBERS table (register, factor,
///    offset) and the `decode_basic_config_data_` / `_voltage_protection_`
///    / `_temperature_protection_` / `_current_protection_data_` decoders
///    (byte index = `3 + (register - frame_base_register) * 2`, read
///    `(raw - offset) / factor`).
class BmsParameter {
  final String id;
  final String label;
  final String group;
  final String unit;
  final BmsParameterType type;
  final double minValue;
  final double maxValue;
  final double step;

  /// Labels for [BmsParameterType.choice] parameters, in wire order.
  final List<String>? options;

  // ---- JK02 protocol binding ------------------------------------------------
  /// Byte offset of this value in the 300-byte JK02 settings frame (type
  /// 0x01). Read as a little-endian u32; user value = raw * [jkRawFactor].
  final int? jkFrameOffset;

  /// JK02 holding register used to write this setting back to hardware.
  /// (The settings-frame offsets above do NOT equal the write registers —
  /// e.g. "Cell OVP recovery" reads at offset 22 but writes to register
  /// 0x05 — so the write path must use this independent table.)
  final int? jkRegister;

  /// JK02_32S write register where it differs from [jkRegister] (JK02_32S
  /// shifts a few registers: balancing-start 0x26->0x22, SCP delay 0x25->0x21).
  /// Null means the 24S register applies to both variants.
  final int? jkRegister32s;

  /// Resolves the write register for the connected protocol variant.
  int? jkWriteRegisterFor(bool is32s) => is32s ? (jkRegister32s ?? jkRegister) : jkRegister;

  /// Convert read raw -> user value: value = raw * [jkRawFactor].
  final double jkRawFactor;

  /// Byte length (1 or 4) carried in the JK02 command frame's length byte.
  final int jkWriteLength;

  /// True when the raw value is a signed little-endian i32 (JK02 temperature
  /// protections can go below zero).
  final bool jkSigned;

  // ---- Daly protocol binding ------------------------------------------------
  /// Daly D2 holding register (settings block 0x0080..0x00A8). Read/write
  /// conversion: user value = (raw - [dalyOffset]) / [dalyFactor],
  /// write raw = value * [dalyFactor] + [dalyOffset].
  final int? dalyRegister;
  final double dalyFactor;
  final double dalyOffset;

  // ---- KS48100 protocol binding ---------------------------------------------
  /// KS config frame type that carries this value (0x04 basic, 0x05 voltage
  /// protection, 0x06 temperature protection, 0x07 current protection).
  final int? ksFrameType;

  /// Byte index inside the KS config frame (big-endian u16 there).
  final int? ksByteIndex;

  /// user value = (raw - [ksOffset]) / [ksFactor]; write raw =
  /// value * [ksFactor] + [ksOffset].
  final double ksFactor;
  final double ksOffset;

  /// KS write register (the `reg` byte in `7B reg 02 hi lo 7D`), derived from
  /// frame type + byte index: register = frame_base + (byteIndex-3)/2, where
  /// frame_base = (ksFrameType & 0x03) maps 0x04->0x10, 0x05->0x20,
  /// 0x06->0x30, 0x07->0x40. Matches the upstream NUMBERS table.
  int? get ksRegister {
    if (ksFrameType == null || ksByteIndex == null) return null;
    final base = ((ksFrameType! & 0x03) + 1) * 0x10;
    return base + ((ksByteIndex! - 3) >> 1);
  }

  const BmsParameter({
    required this.id,
    required this.label,
    required this.group,
    this.unit = '',
    this.type = BmsParameterType.number,
    this.minValue = double.negativeInfinity,
    this.maxValue = double.infinity,
    this.step = 1,
    this.options,
    this.jkFrameOffset,
    this.jkRegister,
    this.jkRegister32s,
    this.jkRawFactor = 0.001,
    this.jkWriteLength = 4,
    this.jkSigned = false,
    this.dalyRegister,
    this.dalyFactor = 1.0,
    this.dalyOffset = 0.0,
    this.ksFrameType,
    this.ksByteIndex,
    this.ksFactor = 1.0,
    this.ksOffset = 0.0,
  });

  bool get isJK02 => jkFrameOffset != null || jkRegister != null;
  bool get isDaly => dalyRegister != null;
  bool get isKesa => ksFrameType != null;
}

/// The most recent set of BMS parameter values decoded from real hardware
/// frames. Values are stored as user-facing units (volts, amps, °C, Ah...),
/// toggles as 0.0/1.0 and choices as their option index.
class BmsSettingsSnapshot {
  final BmsBrand brand;
  final Map<String, double> values;
  final DateTime timestamp;

  const BmsSettingsSnapshot({
    required this.brand,
    required this.values,
    required this.timestamp,
  });

  static BmsSettingsSnapshot empty(BmsBrand brand) =>
      BmsSettingsSnapshot(brand: brand, values: const {}, timestamp: DateTime.now());

  BmsSettingsSnapshot mergeWith(Map<String, double> incoming) {
    return BmsSettingsSnapshot(
      brand: brand,
      values: {...values, ...incoming},
      timestamp: DateTime.now(),
    );
  }

  double? valueFor(BmsParameter p) => values[p.id];
}

/// Identifying details of the connected BMS hardware, decoded from the
/// JK02 device-info frame (frame type 0x03) by [BmsProtocolHelper].
class BmsModelInfo {
  final String modelName;
  final String hardwareVersion;
  final String softwareVersion;
  final int uptimeSeconds;
  final int powerOnCount;

  const BmsModelInfo({
    required this.modelName,
    required this.hardwareVersion,
    required this.softwareVersion,
    required this.uptimeSeconds,
    required this.powerOnCount,
  });
}

/// Static, per-brand catalog of editable parameters. A brand absent from
/// [forBrand] (or returning null) simply has no verified settings protocol
/// yet — the UI shows an honest "no settings available" state instead of
/// fabricating fields the hardware doesn't support.
class BmsParameterSchema {
  static List<BmsParameter>? forBrand(BmsBrand brand) {
    switch (brand) {
      case BmsBrand.jkbms:
        return _jk02;
      case BmsBrand.daly:
        return _daly;
      case BmsBrand.ks:
        return _ks;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // JK02 (JK-BMS). Read offsets and write registers from syssi's
  // jk_bms_ble.cpp `decode_jk02_settings_` (offsets 6..138) and
  // number/__init__.py NUMBERS table (write registers + factors).
  // Factors are the *raw-to-user* factor (reads multiply by it); the write
  // path divides by it (raw = user / factor).
  // Two registers differ on JK02_32S (balancing-start 0x26->0x22, SCP delay
  // 0x25->0x21); those carry [jkRegister32s]. Offsets 106/110 are Mosfet
  // OTP / OTP recovery — the JK02 settings frame carries no separate
  // discharge-undertemperature pair, so it isn't exposed.
  // ---------------------------------------------------------------------------
  static final List<BmsParameter> _jk02 = [
    // Protection — cell voltages (raw = mV stored as u32 LE)
    BmsParameter(
      id: 'cellUvp', label: 'Cell Undervoltage Protection', group: 'Cell protection',
      unit: 'V', minValue: 2.0, maxValue: 4.0, step: 0.001,
      jkFrameOffset: 10, jkRegister: 0x02, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'cellUvpRecovery', label: 'Cell Undervoltage Recovery', group: 'Cell protection',
      unit: 'V', minValue: 2.0, maxValue: 4.0, step: 0.001,
      jkFrameOffset: 14, jkRegister: 0x03, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'cellOvp', label: 'Cell Overvoltage Protection', group: 'Cell protection',
      unit: 'V', minValue: 3.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 18, jkRegister: 0x04, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'cellOvpRecovery', label: 'Cell Overvoltage Recovery', group: 'Cell protection',
      unit: 'V', minValue: 3.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 22, jkRegister: 0x05, jkRawFactor: 0.001,
    ),

    // Protection — pack voltages, currents
    BmsParameter(
      id: 'powerOffVoltage', label: 'Power Off Voltage', group: 'Pack protection',
      unit: 'V', minValue: 2.0, maxValue: 3.7, step: 0.001,
      jkFrameOffset: 46, jkRegister: 0x0B, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'maxChargeCurrent', label: 'Max Charge Current', group: 'Pack protection',
      unit: 'A', minValue: 1.0, maxValue: 200.0, step: 0.01,
      jkFrameOffset: 50, jkRegister: 0x0C, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'maxDischargeCurrent', label: 'Max Discharge Current', group: 'Pack protection',
      unit: 'A', minValue: 1.0, maxValue: 1200.0, step: 0.1,
      jkFrameOffset: 62, jkRegister: 0x0F, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'chargeOcpDelay', label: 'Charge Overcurrent Delay', group: 'Pack protection',
      unit: 's', minValue: 0, maxValue: 600, step: 1,
      jkFrameOffset: 54, jkRegister: 0x0D, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'chargeOcpRecovery', label: 'Charge Overcurrent Recovery', group: 'Pack protection',
      unit: 's', minValue: 0, maxValue: 600, step: 1,
      jkFrameOffset: 58, jkRegister: 0x0E, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'dischargeOcpDelay', label: 'Discharge Overcurrent Delay', group: 'Pack protection',
      unit: 's', minValue: 0, maxValue: 600, step: 1,
      jkFrameOffset: 66, jkRegister: 0x10, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'dischargeOcpRecovery', label: 'Discharge Overcurrent Recovery', group: 'Pack protection',
      unit: 's', minValue: 0, maxValue: 600, step: 1,
      jkFrameOffset: 70, jkRegister: 0x11, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'shortCircuitRecovery', label: 'Short Circuit Recovery', group: 'Pack protection',
      unit: 's', minValue: 0, maxValue: 600, step: 1,
      jkFrameOffset: 74, jkRegister: 0x12, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'shortCircuitDelay', label: 'Short Circuit Delay', group: 'Pack protection',
      unit: 'μs', minValue: 0, maxValue: 1000000, step: 1,
      jkFrameOffset: 134, jkRegister: 0x25, jkRegister32s: 0x21, jkRawFactor: 1.0,
    ),

    // Protection — temperatures (raw is signed i32)
    BmsParameter(
      id: 'chargeOtp', label: 'Charge Overtemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 82, jkRegister: 0x14, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'chargeOtpRecovery', label: 'Charge Overtemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 86, jkRegister: 0x15, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'dischargeOtp', label: 'Discharge Overtemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 90, jkRegister: 0x16, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'dischargeOtpRecovery', label: 'Discharge Overtemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 94, jkRegister: 0x17, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'chargeUtp', label: 'Charge Undertemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 98, jkRegister: 0x18, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'chargeUtpRecovery', label: 'Charge Undertemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      jkFrameOffset: 102, jkRegister: 0x19, jkRawFactor: 0.1, jkSigned: true,
    ),
BmsParameter(
      id: 'mosOtp', label: 'Mosfet Overtemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 110, step: 1,
      jkFrameOffset: 106, jkRegister: 0x1A, jkRawFactor: 0.1, jkSigned: true,
    ),
    BmsParameter(
      id: 'mosOtpRecovery', label: 'Mosfet Overtemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 110, step: 1,
      jkFrameOffset: 110, jkRegister: 0x1B, jkRawFactor: 0.1, jkSigned: true,
    ),

    // Balancing
    BmsParameter(
      id: 'balanceTriggerVoltage', label: 'Balance Trigger Voltage', group: 'Balancing',
      unit: 'V', minValue: 0.003, maxValue: 3.65, step: 0.001,
      jkFrameOffset: 26, jkRegister: 0x06, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'balancingStartVoltage', label: 'Balancing Start Voltage', group: 'Balancing',
      unit: 'V', minValue: 1.0, maxValue: 4.2, step: 0.001,
      jkFrameOffset: 138, jkRegister: 0x26, jkRegister32s: 0x22, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'maxBalanceCurrent', label: 'Max Balance Current', group: 'Balancing',
      unit: 'A', minValue: 0.1, maxValue: 10.0, step: 0.001,
      jkFrameOffset: 78, jkRegister: 0x13, jkRawFactor: 0.001,
    ),

    // Capacity
    BmsParameter(
      id: 'cellCount', label: 'Cell Count', group: 'Capacity',
      unit: 'cells', minValue: 2, maxValue: 32, step: 1,
      jkFrameOffset: 114, jkRegister: 0x1C, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'nominalCapacity', label: 'Nominal Capacity', group: 'Capacity',
      unit: 'Ah', minValue: 2, maxValue: 20000, step: 1,
      jkFrameOffset: 130, jkRegister: 0x20, jkRawFactor: 0.001,
    ),

    // Charging curve
    BmsParameter(
      id: 'soc100Voltage', label: 'SOC 100% Voltage', group: 'Charging curve',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 30, jkRegister: 0x07, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'soc0Voltage', label: 'SOC 0% Voltage', group: 'Charging curve',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 34, jkRegister: 0x08, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'requestChargeVoltage', label: 'Request Charge Voltage (RCV)', group: 'Charging curve',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 38, jkRegister: 0x09, jkRawFactor: 0.001,
    ),
    BmsParameter(
      id: 'requestFloatVoltage', label: 'Request Float Voltage (RFV)', group: 'Charging curve',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      jkFrameOffset: 42, jkRegister: 0x0A, jkRawFactor: 0.001,
    ),

    // Switches (reported by the settings frame; written via the same
    // registers the Control tab already uses)
    BmsParameter(
      id: 'chargeSwitch', label: 'Charging', group: 'Switches',
      type: BmsParameterType.toggle,
      jkFrameOffset: 118, jkRegister: 0x1D, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'dischargeSwitch', label: 'Discharging', group: 'Switches',
      type: BmsParameterType.toggle,
      jkFrameOffset: 122, jkRegister: 0x1E, jkRawFactor: 1.0,
    ),
    BmsParameter(
      id: 'balanceSwitch', label: 'Balancer', group: 'Switches',
      type: BmsParameterType.toggle,
      jkFrameOffset: 126, jkRegister: 0x1F, jkRawFactor: 1.0,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Daly Smart BMS — register 0x0080 block, 41 registers, ((raw-offset)/factor).
  // ---------------------------------------------------------------------------
  static final List<BmsParameter> _daly = [
    // Configuration
    BmsParameter(
      id: 'ratedCapacity', label: 'Rated Capacity', group: 'Configuration',
      unit: 'Ah', minValue: 0, maxValue: 6553.5, step: 0.1,
      dalyRegister: 0x0080, dalyFactor: 10, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellVoltageReference', label: 'Cell Voltage Reference', group: 'Configuration',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x0081, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'acquisitionBoardCount', label: 'Acquisition Boards', group: 'Configuration',
      minValue: 0, maxValue: 3, step: 1,
      dalyRegister: 0x0082, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board1CellCount', label: 'Board 1 Cell Count', group: 'Configuration',
      minValue: 0, maxValue: 24, step: 1,
      dalyRegister: 0x0083, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board2CellCount', label: 'Board 2 Cell Count', group: 'Configuration',
      minValue: 0, maxValue: 24, step: 1,
      dalyRegister: 0x0084, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board3CellCount', label: 'Board 3 Cell Count', group: 'Configuration',
      minValue: 0, maxValue: 24, step: 1,
      dalyRegister: 0x0085, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board1TempSensors', label: 'Board 1 Temp. Sensors', group: 'Configuration',
      minValue: 0, maxValue: 12, step: 1,
      dalyRegister: 0x0086, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board2TempSensors', label: 'Board 2 Temp. Sensors', group: 'Configuration',
      minValue: 0, maxValue: 12, step: 1,
      dalyRegister: 0x0087, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'board3TempSensors', label: 'Board 3 Temp. Sensors', group: 'Configuration',
      minValue: 0, maxValue: 12, step: 1,
      dalyRegister: 0x0088, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'batteryType', label: 'Battery Type', group: 'Configuration',
      minValue: 0, maxValue: 2, step: 1,
      options: const ['LiFePO4', 'Ternary Lithium', 'Lithium Titanate'],
      dalyRegister: 0x0089, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'sleepWaitTime', label: 'Sleep Wait Time', group: 'Configuration',
      unit: 's', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x008A, dalyFactor: 1, dalyOffset: 0,
    ),

    // Cell voltage protection
    BmsParameter(
      id: 'cellOvpWarning', label: 'Cell Overvoltage Warning', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x008B, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellOvpAlarm', label: 'Cell Overvoltage Alarm', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x008C, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellUvpWarning', label: 'Cell Undervoltage Warning', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x008D, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellUvpAlarm', label: 'Cell Undervoltage Alarm', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x008E, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellVoltageDifferenceWarning', label: 'Cell Voltage Difference Warning', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x009F, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'cellVoltageDifferenceAlarm', label: 'Cell Voltage Difference Alarm', group: 'Cell voltage',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x00A0, dalyFactor: 1, dalyOffset: 0,
    ),

    // Pack voltage protection
    BmsParameter(
      id: 'totalOvpWarning', label: 'Pack Overvoltage Warning', group: 'Pack voltage',
      unit: 'V', minValue: 0, maxValue: 6553.5, step: 0.1,
      dalyRegister: 0x008F, dalyFactor: 10, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'totalOvpAlarm', label: 'Pack Overvoltage Alarm', group: 'Pack voltage',
      unit: 'V', minValue: 0, maxValue: 6553.5, step: 0.1,
      dalyRegister: 0x0090, dalyFactor: 10, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'totalUvpWarning', label: 'Pack Undervoltage Warning', group: 'Pack voltage',
      unit: 'V', minValue: 0, maxValue: 6553.5, step: 0.1,
      dalyRegister: 0x0091, dalyFactor: 10, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'totalUvpAlarm', label: 'Pack Undervoltage Alarm', group: 'Pack voltage',
      unit: 'V', minValue: 0, maxValue: 6553.5, step: 0.1,
      dalyRegister: 0x0092, dalyFactor: 10, dalyOffset: 0,
    ),

    // Current protection (offset-scaled two's complement)
    BmsParameter(
      id: 'chargeOvercurrentWarning', label: 'Charge Overcurrent Warning', group: 'Current',
      unit: 'A', minValue: -3000, maxValue: 3553.5, step: 0.1,
      dalyRegister: 0x0093, dalyFactor: 10, dalyOffset: 30000,
    ),
    BmsParameter(
      id: 'chargeOvercurrentAlarm', label: 'Charge Overcurrent Alarm', group: 'Current',
      unit: 'A', minValue: -3000, maxValue: 3553.5, step: 0.1,
      dalyRegister: 0x0094, dalyFactor: 10, dalyOffset: 30000,
    ),
    BmsParameter(
      id: 'dischargeOvercurrentWarning', label: 'Discharge Overcurrent Warning', group: 'Current',
      unit: 'A', minValue: -3000, maxValue: 3553.5, step: 0.1,
      dalyRegister: 0x0095, dalyFactor: 10, dalyOffset: 30000,
    ),
    BmsParameter(
      id: 'dischargeOvercurrentAlarm', label: 'Discharge Overcurrent Alarm', group: 'Current',
      unit: 'A', minValue: -3000, maxValue: 3553.5, step: 0.1,
      dalyRegister: 0x0096, dalyFactor: 10, dalyOffset: 30000,
    ),

    // Temperature protection
    BmsParameter(
      id: 'chargeOverTempWarning', label: 'Charge Overtemperature Warning', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x0097, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'chargeOverTempAlarm', label: 'Charge Overtemperature Alarm', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x0098, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'chargeUnderTempWarning', label: 'Charge Undertemperature Warning', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x0099, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'chargeUnderTempAlarm', label: 'Charge Undertemperature Alarm', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x009A, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'dischargeOverTempWarning', label: 'Discharge Overtemperature Warning', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x009B, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'dischargeOverTempAlarm', label: 'Discharge Overtemperature Alarm', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x009C, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'dischargeUnderTempWarning', label: 'Discharge Undertemperature Warning', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x009D, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'dischargeUnderTempAlarm', label: 'Discharge Undertemperature Alarm', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x009E, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'mosOtpAlarm', label: 'MOSFET Overtemperature Alarm', group: 'Temperature',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      dalyRegister: 0x00A8, dalyFactor: 1, dalyOffset: 40,
    ),
    BmsParameter(
      id: 'temperatureDifferenceWarning', label: 'Temperature Difference Warning', group: 'Temperature',
      unit: '°C', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x00A1, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'temperatureDifferenceAlarm', label: 'Temperature Difference Alarm', group: 'Temperature',
      unit: '°C', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x00A2, dalyFactor: 1, dalyOffset: 0,
    ),

    // Balancing
    BmsParameter(
      id: 'balancingActivationVoltage', label: 'Balancing Activation Voltage', group: 'Balancing',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x00A3, dalyFactor: 1, dalyOffset: 0,
    ),
    BmsParameter(
      id: 'balancingActivationDifference', label: 'Balancing Activation Difference', group: 'Balancing',
      unit: 'mV', minValue: 0, maxValue: 65535, step: 1,
      dalyRegister: 0x00A4, dalyFactor: 1, dalyOffset: 0,
    ),

    // SOC
    BmsParameter(
      id: 'socSetting', label: 'State of Charge Setting', group: 'SOC',
      unit: '%', minValue: 0, maxValue: 100, step: 0.1,
      dalyRegister: 0x00A7, dalyFactor: 10, dalyOffset: 0,
    ),
  ];

  // ---------------------------------------------------------------------------
  // KS48100 — config frames 0x04..0x07, byte index 3 + (reg-base)*2, decoded
  // as big-endian u16s, user value (raw - offset)/factor.
  // Fully matches syssi's decoders. Deliberately excluded:
  //   * delay fields (0x22/0x25/0x28/0x2B/0x32/0x35/0x38/0x3B/0x41/0x44/0x45)
  //     — upstream reads them ÷1000 (seconds) but writes them ÷1 (ms), so
  //     showing a value back after writing would be wrong,
  //   * register capacity 0x1A/0x1B/0x1C — declared in the YAML NUMBERS table
  //     but never decoded by any upstream config read, so nothing can be
  //     read back to confirm a write.
  // ---------------------------------------------------------------------------
  static final List<BmsParameter> _ks = [
    // Frame 0x04 — basic config (register base 0x10)
    BmsParameter(
      id: 'cellFullVoltage', label: 'Cell Full Voltage', group: 'Basic config',
      unit: 'V', minValue: 3.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x10 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'cellCutoffVoltage', label: 'Cell Cutoff Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.0, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x11 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'balanceOpenVoltage', label: 'Balance Open Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x12 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'balanceOpenVoltageDiff', label: 'Balance Open Voltage Difference', group: 'Basic config',
      unit: 'V', minValue: 0.001, maxValue: 1.0, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x13 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'soc80Voltage', label: 'SOC 80% Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x16 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'soc60Voltage', label: 'SOC 60% Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x17 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'soc40Voltage', label: 'SOC 40% Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x18 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'soc20Voltage', label: 'SOC 20% Voltage', group: 'Basic config',
      unit: 'V', minValue: 2.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x04, ksByteIndex: 3 + (0x19 - 0x10) * 2, ksFactor: 1000, ksOffset: 0,
    ),

    // Frame 0x05 — voltage protection (register base 0x20)
    BmsParameter(
      id: 'cellOverVoltageProtection', label: 'Cell Overvoltage Protection', group: 'Voltage protection',
      unit: 'V', minValue: 3.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x20 - 0x20) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'cellOverVoltageRecovery', label: 'Cell Overvoltage Recovery', group: 'Voltage protection',
      unit: 'V', minValue: 3.0, maxValue: 4.5, step: 0.001,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x21 - 0x20) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'cellUnderVoltageProtection', label: 'Cell Undervoltage Protection', group: 'Voltage protection',
      unit: 'V', minValue: 2.0, maxValue: 4.0, step: 0.001,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x23 - 0x20) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'cellUnderVoltageRecovery', label: 'Cell Undervoltage Recovery', group: 'Voltage protection',
      unit: 'V', minValue: 2.0, maxValue: 4.0, step: 0.001,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x24 - 0x20) * 2, ksFactor: 1000, ksOffset: 0,
    ),
    BmsParameter(
      id: 'packOverVoltageProtection', label: 'Pack Overvoltage Protection', group: 'Voltage protection',
      unit: 'V', minValue: 10.0, maxValue: 655.0, step: 0.01,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x26 - 0x20) * 2, ksFactor: 100, ksOffset: 0,
    ),
    BmsParameter(
      id: 'packOverVoltageRecovery', label: 'Pack Overvoltage Recovery', group: 'Voltage protection',
      unit: 'V', minValue: 10.0, maxValue: 655.0, step: 0.01,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x27 - 0x20) * 2, ksFactor: 100, ksOffset: 0,
    ),
    BmsParameter(
      id: 'packUnderVoltageProtection', label: 'Pack Undervoltage Protection', group: 'Voltage protection',
      unit: 'V', minValue: 10.0, maxValue: 655.0, step: 0.01,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x29 - 0x20) * 2, ksFactor: 100, ksOffset: 0,
    ),
    BmsParameter(
      id: 'packUnderVoltageRecovery', label: 'Pack Undervoltage Recovery', group: 'Voltage protection',
      unit: 'V', minValue: 10.0, maxValue: 655.0, step: 0.01,
      ksFrameType: 0x05, ksByteIndex: 3 + (0x2A - 0x20) * 2, ksFactor: 100, ksOffset: 0,
    ),

    // Frame 0x06 — temperature protection (register base 0x30)
    BmsParameter(
      id: 'chargeOverTempProtection', label: 'Charge Overtemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x30 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'chargeOverTempRecovery', label: 'Charge Overtemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x31 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'chargeUnderTempProtection', label: 'Charge Undertemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x33 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'chargeUnderTempRecovery', label: 'Charge Undertemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x34 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'dischargeOverTempProtection', label: 'Discharge Overtemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x36 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'dischargeOverTempRecovery', label: 'Discharge Overtemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x37 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'dischargeUnderTempProtection', label: 'Discharge Undertemperature', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x39 - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),
    BmsParameter(
      id: 'dischargeUnderTempRecovery', label: 'Discharge Undertemperature Recovery', group: 'Temperature protection',
      unit: '°C', minValue: -40, maxValue: 100, step: 1,
      ksFrameType: 0x06, ksByteIndex: 3 + (0x3A - 0x30) * 2, ksFactor: 10, ksOffset: 2731,
    ),

    // Frame 0x07 — current protection (register base 0x40)
    BmsParameter(
      id: 'chargeOverCurrentProtection', label: 'Charge Overcurrent Protection', group: 'Current protection',
      unit: 'A', minValue: 0, maxValue: 650, step: 0.01,
      ksFrameType: 0x07, ksByteIndex: 3 + (0x40 - 0x40) * 2, ksFactor: 100, ksOffset: 0,
    ),
    BmsParameter(
      id: 'dischargeOverCurrentProtection', label: 'Discharge Overcurrent Protection', group: 'Current protection',
      unit: 'A', minValue: 0, maxValue: 650, step: 0.01,
      ksFrameType: 0x07, ksByteIndex: 3 + (0x43 - 0x40) * 2, ksFactor: 100, ksOffset: 0,
    ),
  ];
}