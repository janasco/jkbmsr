import 'dart:typed_data';
import '../models/bms_models.dart';
import '../models/bms_parameter.dart';

class BmsProtocolHelper {
  // Common BMS BLE Service and Characteristic UUIDs
  static const String jkBmsServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String jkBmsCharUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";
  
  static const String jk02ServiceUuid = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String jk02WriteCharUuid = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String jk02NotifyCharUuid = "0000ff02-0000-1000-8000-00805f9b34fb";

  static const String dalyServiceUuid = "0000fff0-0000-1000-8000-00805f9b34fb";
  static const String dalyNotifyCharUuid = "0000fff1-0000-1000-8000-00805f9b34fb";
  static const String dalyCharUuid = "0000fff2-0000-1000-8000-00805f9b34fb";

  static const String jbdServiceUuid = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String jbdWriteCharUuid = "0000ff02-0000-1000-8000-00805f9b34fb";
  static const String jbdNotifyCharUuid = "0000ff01-0000-1000-8000-00805f9b34fb";

  static const String antServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String antCharUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  // Same 0xFF00/01/02 triad as JBD on the wire — brand is disambiguated by
  // name/frame content, not the service UUID, for either of these.
  static const String seplosServiceUuid = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String seplosNotifyCharUuid = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String seplosControlCharUuid = "0000ff02-0000-1000-8000-00805f9b34fb";

  // JBD/Xiaoxiang MOS control register (0xDD 0x5A 0xE1 ... 0x77 frame).
  static const int jbdMosControlRegister = 0xE1;

  /// Standard Modbus CRC16 (init 0xFFFF, reflected poly 0xA001), stored
  /// little-endian on the wire. Used by Daly's D2 protocol and ANT BMS.
  static int modbusCrc16(List<int> data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= b & 0xFF;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// XMODEM CRC16 (init 0x0000, poly 0x1021, MSB-first, no reflection),
  /// stored big-endian on the wire. Used by Seplos.
  static int xmodemCrc16(List<int> data) {
    int crc = 0x0000;
    for (final b in data) {
      crc ^= (b & 0xFF) << 8;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }

  // Only 3 distinct UUID values exist across all 5 brands (0xFFE0, 0xFF00,
  // 0xFFF0 — each reused by 2+ brands), so this set is small by nature.
  static final Set<String> _knownBmsServiceUuids = {
    jkBmsServiceUuid, // == antServiceUuid
    jk02ServiceUuid, // == jbdServiceUuid == seplosServiceUuid
    dalyServiceUuid,
  };

  /// True if any advertised service UUID matches a known BMS protocol's
  /// GATT service. This is a name-independent signal — useful because many
  /// of these Bluetooth-UART bridge modules advertise a blank/generic name
  /// (the real name only becomes available via GATT after connecting), or
  /// because the user renamed the device in the BMS's own app and it no
  /// longer matches any of [detectBrandFromName]'s patterns.
  static bool looksLikeBmsService(Iterable<String> advertisedServiceUuids128) {
    return advertisedServiceUuids128.any((u) => _knownBmsServiceUuids.contains(u.toLowerCase()));
  }

  static BmsBrand detectBrandFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('jk') || lower.contains('jkbms') || lower.startsWith('b1a') || lower.startsWith('b2a') || lower.startsWith('bd6a') || lower.startsWith('pb2a')) {
      return BmsBrand.jkbms;
    } else if (lower.startsWith('dl') || lower.contains('daly')) {
      return BmsBrand.daly;
    } else if (lower.contains('xiaoxiang') || lower.contains('jbd') || lower.startsWith('sp') || lower.contains('smartbms')) {
      return BmsBrand.jbd;
    } else if (lower.startsWith('ant') || lower.contains('antbms')) {
      return BmsBrand.ant;
    } else if (lower.contains('seplos')) {
      return BmsBrand.seplos;
    } else if (lower.contains('tianpower')) {
      return BmsBrand.tianpower;
    } else if (lower.contains('basen')) {
      return BmsBrand.basen;
    } else if (lower.contains('ks48100') || lower.startsWith('ks-')) {
      return BmsBrand.ks;
    } else if (lower.contains('offgridtec') || lower.contains('ogt')) {
      return BmsBrand.ogt;
    } else if (lower.contains('topband')) {
      return BmsBrand.topband;
    } else if (lower.contains('lolan')) {
      return BmsBrand.lolan;
    }
    return BmsBrand.unknown;
  }

  // ===== JK-BMS JK02 protocol =====
  // Verified byte-for-byte against syssi/esphome-jk-bms (jk_bms_ble.cpp /
  // switch/__init__.py), a widely-deployed, community-maintained JK-BMS
  // integration. Our previous implementation here used an invented
  // "0x4E 0x57" frame format that doesn't match any real JK-BMS protocol
  // and a `parseJkFrame` that fabricated most fields outright — replaced
  // below with the actual JK02 wire format.
  //
  // Command/write frame (20 bytes): AA 55 90 EB [register] [len] [value,
  // 4 bytes LE] [zero padding] [crc], crc = sum(bytes[0..18]) & 0xFF.
  // Response frame (300 bytes, fixed size even though the buffer may hold
  // up to ~320): 55 AA EB 90 [type] [counter] ... [crc at byte 299],
  // crc = sum(bytes[0..298]) & 0xFF. Real hardware sends this fragmented
  // across many ~20-byte BLE notifications — callers must accumulate
  // fragments into one buffer (see [isCompleteJk02Frame]) before parsing;
  // a single ~20-byte fragment is never a complete frame on its own.

  static const int jk02CommandCellInfo = 0x96; // -> response frame type 0x02
  static const int jk02CommandDeviceInfo = 0x97; // -> response frame type 0x03

  /// JK02 holding-register addresses for each switch. Charge/discharge/
  /// balancer (0x1D/0x1E/0x1F) are identical across the JK02_24S and
  /// JK02_32S protocol sub-variants; the rest are JK02_32S-only registers
  /// (writing them on 24S hardware should just have no effect, per that
  /// variant's register table).
  static const Map<String, int> jk02SwitchRegisters = {
    'charge': 0x1D,
    'discharge': 0x1E,
    'balance': 0x1F,
    'emergency': 0x6B,
    'tempSensor': 0x28,
    'display': 0x2B,
    'smartSleep': 0x2D,
    'timedData': 0x2F,
    'floatMode': 0x30,
    'dryArm': 0x32,
    'ocp2': 0x33,
    'ocp3': 0x34,
  };

  static const int _jk02FrameSize = 300;

  static Uint8List buildJk02Command(int register, {int value = 0, int length = 0}) {
    final frame = Uint8List(20);
    frame[0] = 0xAA;
    frame[1] = 0x55;
    frame[2] = 0x90;
    frame[3] = 0xEB;
    frame[4] = register;
    frame[5] = length;
    frame[6] = value & 0xFF;
    frame[7] = (value >> 8) & 0xFF;
    frame[8] = (value >> 16) & 0xFF;
    frame[9] = (value >> 24) & 0xFF;
    int sum = 0;
    for (int i = 0; i < 19; i++) {
      sum += frame[i];
    }
    frame[19] = sum & 0xFF;
    return frame;
  }

  static Uint8List buildJk02SwitchCommand(int register, bool enable) {
    return buildJk02Command(register, value: enable ? 1 : 0, length: 0x04);
  }

  /// True once [buffer] holds a complete, CRC-valid 300-byte JK02 response
  /// at its start. Feed accumulated fragments in here after every BLE
  /// notification; once true, parse and then clear the buffer.
  static bool isCompleteJk02Frame(List<int> buffer) {
    if (buffer.length < _jk02FrameSize) return false;
    int sum = 0;
    for (int i = 0; i < _jk02FrameSize - 1; i++) {
      sum += buffer[i];
    }
    return (sum & 0xFF) == buffer[_jk02FrameSize - 1];
  }

  static int _u16(List<int> d, int o) => d[o] | (d[o + 1] << 8);

  static int _u32(List<int> d, int o) =>
      (d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)) & 0xFFFFFFFF;

  static int _i16(List<int> d, int o) {
    final v = _u16(d, o);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _i32(List<int> d, int o) {
    final v = _u32(d, o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Parses a JK02 "device info" (frame type 0x03) response and returns
  /// whether the hardware uses the 32-cell register layout instead of the
  /// 24-cell one. Real JK02 hardware requires this to be requested (and
  /// its response parsed) *before* the cell-info command will get a
  /// response at all — the connected pack's hardware-version string
  /// (offset 22, e.g. "11.XW") decides the layout: major number >= 11
  /// means 32-cell. Cross-checked against jkbmsr-firmware's
  /// Jk02Decoder.cpp, which itself ports syssi/esphome-jk-bms's logic and
  /// has been validated against real 24S hardware captures.
  static bool? parseJk02DeviceInfoIs32s(List<int> data) {
    if (data.length < _jk02FrameSize) return null;
    if (data[0] != 0x55 || data[1] != 0xAA || data[2] != 0xEB || data[3] != 0x90) return null;
    if (data[4] != 0x03) return null;
    if (!isCompleteJk02Frame(data)) return null;

    final hwVersionBytes = data.sublist(22, 30).takeWhile((b) => b != 0);
    final hwVersionText = String.fromCharCodes(hwVersionBytes);
    final match = RegExp(r'\d+').firstMatch(hwVersionText);
    if (match == null) return false;
    final major = int.tryParse(match.group(0)!) ?? 0;
    return major >= 11;
  }

  /// Parses a complete 300-byte JK02 "device info" (frame type 0x03)
  /// response into a [BmsModelInfo]. Verified against syssi's
  /// `decode_device_info_` (jk_bms_ble.cpp:1583) — offsets 6 (model, 16B),
  /// 22 (hardware version, 8B), 30 (software version, 8B), 38 (uptime u32),
  /// 42 (power-on count u32). Null on any structural/CRC failure.
  static BmsModelInfo? parseJk02DeviceInfoFrame(List<int> data) {
    if (data.length < _jk02FrameSize) return null;
    if (data[0] != 0x55 || data[1] != 0xAA || data[2] != 0xEB || data[3] != 0x90) return null;
    if (data[4] != 0x03) return null;
    if (!isCompleteJk02Frame(data)) return null;

    String text(List<int> slice) =>
        String.fromCharCodes(slice.takeWhile((b) => b != 0));

    return BmsModelInfo(
      modelName: text(data.sublist(6, 22)),
      hardwareVersion: text(data.sublist(22, 30)),
      softwareVersion: text(data.sublist(30, 38)),
      uptimeSeconds: _u32(data, 38),
      powerOnCount: _u32(data, 42),
    );
  }

  /// Parses a complete 300-byte JK02 "settings" (frame type 0x01) response
  /// into a map of settings-frame byte offset -> raw little-endian u32/i32.
  /// Only offsets that carry a real setting (6..138, step 4) are produced;
  /// the wire-resistance array and later bytes are ignored. Verified against
  /// syssi's `decode_jk02_settings_` (jk_bms_ble.cpp:1153), which confirms
  /// offsets 6/10/14/18/22 (cells/SOC), 26/30/34/38/42 (balancing/SOC/RCV/
  /// RFV), 46 (power-off), 50 (max chg), 54/58 (chg OCP delay/rec), 62
  /// (max dischg), 66/70 (dischg OCP delay/rec), 74 (SCP rec), 78 (max bal),
  /// 82..110 (temps, incl. mosfet OTP at 106/110), 114 (cell count, byte),
  /// 118/122/126 (charge/discharge/balance switches, bytes), 130 (nominal
  /// capacity), 134 (SCP delay), 138 (balancing start voltage).
  /// Returns null on any structural/CRC failure.
  static Map<int, int>? parseJk02SettingsFrame(List<int> data) {
    if (data.length < _jk02FrameSize) return null;
    if (data[0] != 0x55 || data[1] != 0xAA || data[2] != 0xEB || data[3] != 0x90) return null;
    if (data[4] != 0x01) return null;
    if (!isCompleteJk02Frame(data)) return null;

    final raw = <int, int>{};
    for (int offset = 6; offset <= 78; offset += 4) {
      raw[offset] = _u32(data, offset);
    }
    // Temperature block (82..110) is signed i32 in the upstream decoder:
    // `((int32_t) jk_get_32bit(i)) * 0.1f`, so it must stay signed here or a
    // negative value (e.g. -20.0 °C) would be read back as a huge positive.
    for (int offset = 82; offset <= 110; offset += 4) {
      raw[offset] = _i32(data, offset);
    }
    // Byte-width fields are read as their raw byte so the caller can apply
    // the same * jkRawFactor conversion (factor 1.0 keeps them unchanged).
    raw[114] = data[114];
    raw[118] = data[118];
    raw[122] = data[122];
    raw[126] = data[126];
    raw[130] = _u32(data, 130);
    raw[134] = _u32(data, 134);
    raw[138] = _u32(data, 138);
    return raw;
  }

  /// Parses a complete 300-byte JK02 "cell info" (frame type 0x02)
  /// response. [is32s] must come from a prior [parseJk02DeviceInfoIs32s]
  /// call on the same connection — the 32-cell layout shifts every field
  /// after the cell array by 16 bytes, and every field after the
  /// resistance array by a further 16 (32 total), matching
  /// jkbmsr-firmware's Jk02Decoder.cpp. That firmware's own comments flag
  /// the 32S wire-resistance offset as inferred-but-not-verified against
  /// real 32S hardware (only synthetic test data) — voltage/current/SOC
  /// etc. use the same shift and are considered solid.
  static BmsStatus? parseJk02CellInfoFrame(List<int> data, {bool is32s = false}) {
    if (data.length < _jk02FrameSize) return null;
    if (data[0] != 0x55 || data[1] != 0xAA || data[2] != 0xEB || data[3] != 0x90) return null;
    if (data[4] != 0x02) return null;
    if (!isCompleteJk02Frame(data)) return null;

    try {
      final off = is32s ? 16 : 0;
      final off2 = off * 2;
      final cellSlots = is32s ? 32 : 24;

      final cells = <CellInfo>[];
      for (int i = 0; i < cellSlots; i++) {
        final mv = _u16(data, i * 2 + 6);
        if (mv <= 0) continue;
        final resistanceOhms = _u16(data, i * 2 + 64 + off) * 0.001;
        cells.add(CellInfo(index: i + 1, voltage: mv * 0.001, wireResistance: resistanceOhms));
      }

      final totalVoltage = _u32(data, 118 + off2) * 0.001;
      final currentA = _i32(data, 126 + off2) * 0.001;
      final mosTemp = is32s ? _i16(data, 112 + off2) * 0.1 : _i16(data, 134 + off2) * 0.1;

      return BmsStatus(
        brand: BmsBrand.jkbms,
        modelName: 'JK-BMS',
        soc: data[141 + off2],
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: _u32(data, 142 + off2) * 0.001,
        nominalCapacityAh: _u32(data, 146 + off2) * 0.001,
        cycleCount: _u32(data, 150 + off2),
        totalCycleCapacityAh: _u32(data, 154 + off2) * 0.001,
        cells: cells,
        mosTemp: mosTemp,
        t1Temp: _i16(data, 130 + off2) * 0.1,
        t2Temp: _i16(data, 132 + off2) * 0.1,
        balanceCurrentA: _i16(data, 138 + off2) * 0.001,
        chargeMosEnabled: data[166 + off2] != 0,
        dischargeMosEnabled: data[167 + off2] != 0,
        // jkbmsr-firmware's real-hardware-validated decoder reads this
        // ("legacy" balancing indicator) rather than the alternate byte
        // 169 flag esphome also documents — matched here for consistency
        // across the JKBMSR ecosystem.
        balanceEnabled: data[140 + off2] != 0,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Daly Smart BMS (D2/Modbus protocol) =====
  // Verified against syssi/esphome-daly-bms (daly_bms_ble.cpp,
  // switch/__init__.py). This is a genuine Modbus-RTU-style protocol over
  // BLE — completely different from (and replaces) this file's previous
  // Daly implementation, which used a checksum-sum "0xA5 0x40" UART frame
  // sourced from forum posts describing a different (non-BLE) Daly product
  // line. Frame: D2 [func] [addrHi addrLo] [valueHi valueLo] [crc16 lo hi],
  // crc = modbusCrc16(bytes[0..5]). Read responses: D2 03 [len] [payload]
  // [crc16 hi lo] — note the response CRC is big-endian on the wire while
  // the request CRC is little-endian (both computed the same way).
  static const int dalyFunctionRead = 0x03;
  static const int dalyFunctionWrite = 0x06;
  static const int dalyStatusStartRegister = 0x0000;
  static const int dalyStatusRegisterCount62 = 62;

  static const int dalyRegChargeSwitch = 0x00A5;
  static const int dalyRegDischargeSwitch = 0x00A6;
  static const int dalyRegBalancerSwitch = 0x00CF;

  static Uint8List buildDalyFrame(int function, int address, int value) {
    final frame = Uint8List(8);
    frame[0] = 0xD2;
    frame[1] = function;
    frame[2] = (address >> 8) & 0xFF;
    frame[3] = address & 0xFF;
    frame[4] = (value >> 8) & 0xFF;
    frame[5] = value & 0xFF;
    final crc = modbusCrc16(frame.sublist(0, 6));
    frame[6] = crc & 0xFF;
    frame[7] = (crc >> 8) & 0xFF;
    return frame;
  }

  static Uint8List buildDalyStatusRequest({int registerCount = dalyStatusRegisterCount62}) {
    return buildDalyFrame(dalyFunctionRead, dalyStatusStartRegister, registerCount);
  }

  static Uint8List buildDalySwitchCommand(int register, bool enable) {
    return buildDalyFrame(dalyFunctionWrite, register, enable ? 1 : 0);
  }

  static const int dalySettingsStartRegister = 0x0080;

  /// Total number of adjacent holding registers in the Daly settings block
  /// (0x0080 .. 0x00A8). Verified against syssi's
  /// `daly_bms_ble.cpp:612` settings request: D2 03 read 0x0080 with a
  /// register count of 0x0029 (41), producing a 41*2 = 82-byte payload plus
  /// the 5-byte D2/len/crc wrapper (87 bytes total).
  static const int dalySettingsRegisterCount = 0x29;

  /// Builds the "read the whole settings block" request:
  /// `D2 03 00 80 00 29 [crc]`. The BMS answers with a single settings
  /// frame which [parseDalySettingsFrame] decodes.
  static Uint8List buildDalySettingsRequest() =>
      buildDalyFrame(dalyFunctionRead, dalySettingsStartRegister, dalySettingsRegisterCount);

  /// If [data] is a complete Daly settings response (function 0x03, payload
  /// length 0x52), returns a map of holding register -> raw big-endian u16.
  /// Register lookup: byteIndex = 3 + (register - 0x0080) * 2, exactly as
  /// `decode_settings_data_` reads it (daly_bms_ble.cpp:612). Registers
  /// absent from the frame are simply omitted.
  static Map<int, int>? parseDalySettingsFrame(List<int> data) {
    if (data.length < 3) return null;
    if (data[0] != 0xD2 || data[1] != dalyFunctionRead) return null;
    final payload = data[2];
    if (payload != 0x52) return null;
    if (data.length < 3 + payload + 2) return null;
    final computedCrc = modbusCrc16(data.sublist(0, 3 + payload));
    final remoteCrc = data[3 + payload] | (data[4 + payload] << 8);
    if (computedCrc != remoteCrc) return null;

    final regs = <int, int>{};
    for (int i = 0; i < payload / 2; i++) {
      regs[dalySettingsStartRegister + i] = (data[3 + i * 2] << 8) | data[4 + i * 2];
    }
    return regs;
  }

  /// True once [buffer] holds a complete, CRC-valid Daly status response
  /// (either the 62- or 80-register variant) at its start.
  static bool isCompleteDalyStatusFrame(List<int> buffer) {
    final len = _completeDalyFrameLength(buffer);
    if (len == null) return false;
    final payload = buffer[2];
    final computedCrc = modbusCrc16(buffer.sublist(0, 3 + payload));
    final remoteCrc = buffer[3 + payload] | (buffer[4 + payload] << 8);
    return computedCrc == remoteCrc;
  }

  static int? _completeDalyFrameLength(List<int> buffer) {
    if (buffer.length < 3) return null;
    if (buffer[0] != 0xD2 || buffer[1] != dalyFunctionRead) return null;
    final payload = buffer[2];
    final frameLen = 3 + payload + 2;
    if (buffer.length < frameLen) return null;
    return frameLen;
  }

  /// Parses a complete Daly status response (function 0x03, register 0x0000
  /// read). Big-endian throughout. Accepts both the 62- and 80-register
  /// response sizes; the extra fields (balance current, MOSFET/board temp)
  /// in the 80-register variant are only populated when present.
  static BmsStatus? parseDalyStatusFrame(List<int> data) {
    if (!isCompleteDalyStatusFrame(data)) return null;

    int be16(int o) => (data[o] << 8) | data[o + 1];

    try {
      final cellCount = data[102].clamp(0, 32);
      final cells = <CellInfo>[];
      for (int i = 0; i < cellCount; i++) {
        final mv = be16(3 + i * 2);
        if (mv <= 0) continue;
        cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
      }

      final totalVoltage = be16(83) * 0.1;
      final currentA = (be16(85) - 30000) * 0.1;
      final temperatureSensors = data[104].clamp(0, 8);
      final t1 = temperatureSensors > 0 ? (be16(67) - 40).toDouble() : 0.0;
      final t2 = temperatureSensors > 1 ? (be16(69) - 40).toDouble() : 0.0;

      double mosTemp = 0.0;
      double balanceCurrentA = 0.0;
      if (data.length >= 3 + 160 + 2) {
        // 80-register variant only.
        balanceCurrentA = (be16(131) - 30000) * 0.001;
        mosTemp = (be16(135) - 40).toDouble();
      }

      return BmsStatus(
        brand: BmsBrand.daly,
        modelName: 'Daly Smart BMS',
        soc: (be16(87) * 0.1).round().clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: be16(99) * 0.1,
        // Not present in this status frame (would need the separate
        // Settings frame this app doesn't request) — explicitly zeroed
        // rather than silently inheriting BmsStatus's demo defaults.
        nominalCapacityAh: 0.0,
        cycleCount: be16(105),
        totalCycleCapacityAh: 0.0,
        cells: cells,
        mosTemp: mosTemp,
        t1Temp: t1,
        t2Temp: t2,
        balanceCurrentA: balanceCurrentA,
        chargeMosEnabled: be16(109) == 1,
        dischargeMosEnabled: be16(111) == 1,
        balanceEnabled: be16(107) == 1,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// JBD/Xiaoxiang combined charge+discharge MOS control (register 0xE1).
  /// Both MOSFETs are set in one write — there is no independent
  /// single-switch command on this protocol, so callers must supply the
  /// desired state of both. Frame: DD 5A E1 02 00 [bitmask] [chk_hi]
  /// [chk_lo] 77, where bitmask bit0 = charge MOS disabled, bit1 =
  /// discharge MOS disabled, and checksum = two's complement of
  /// (cmd + len + data bytes).
  static Uint8List buildJbdMosControlCommand({
    required bool chargeEnabled,
    required bool dischargeEnabled,
  }) {
    int bitmask = 0;
    if (!chargeEnabled) bitmask |= 0x01;
    if (!dischargeEnabled) bitmask |= 0x02;

    final frame = Uint8List(9);
    frame[0] = 0xDD;
    frame[1] = 0x5A;
    frame[2] = jbdMosControlRegister;
    frame[3] = 0x02;
    frame[4] = 0x00;
    frame[5] = bitmask;
    final sum = jbdMosControlRegister + 0x02 + 0x00 + bitmask;
    final check = (0x10000 - sum) & 0xFFFF;
    frame[6] = (check >> 8) & 0xFF;
    frame[7] = check & 0xFF;
    frame[8] = 0x77;
    return frame;
  }

  // JBD / Xiaoxiang Command Builders
  static Uint8List buildJbdReadCommand(int commandId) {
    // 0xDD 0xA5 [cmd] 0x00 0xFF 0xFD 0x77
    final frame = Uint8List(7);
    frame[0] = 0xDD;
    frame[1] = 0xA5;
    frame[2] = commandId; // 0x03 = basic info, 0x04 = cell voltages
    frame[3] = 0x00;
    int check = (0x10000 - (commandId + 0x00)) & 0xFFFF;
    frame[4] = (check >> 8) & 0xFF;
    frame[5] = check & 0xFF;
    frame[6] = 0x77;
    return frame;
  }

  // JBD response frame: DD [function] 00 [len] [payload] [crc_hi crc_lo] 77.
  // Checksum = two's complement of sum(status_byte + len_byte + payload) --
  // same formula as request frames. BasicInfo and CellInfo arrive as
  // separate frames (the real hardware always answers BasicInfo first,
  // then CellInfo) -- see [withCells] for combining them into one status.
  static const int jbdCommandBasicInfo = 0x03;
  static const int jbdCommandCellInfo = 0x04;

  static int _jbdChecksum(List<int> data) {
    int sum = 0;
    for (final b in data) {
      sum += b;
    }
    return (0x10000 - sum) & 0xFFFF;
  }

  static int? _completeJbdFrameLength(List<int> buffer) {
    if (buffer.length < 4) return null;
    if (buffer[0] != 0xDD || buffer[2] != 0x00) return null;
    final dataLen = buffer[3];
    final frameLen = 4 + dataLen + 3;
    if (buffer.length < frameLen) return null;
    if (buffer[frameLen - 1] != 0x77) return null;
    return frameLen;
  }

  static bool isCompleteJbdFrame(List<int> buffer) {
    final len = _completeJbdFrameLength(buffer);
    if (len == null) return false;
    final dataLen = buffer[3];
    final computed = _jbdChecksum(buffer.sublist(2, 4 + dataLen));
    final remote = (buffer[len - 3] << 8) | buffer[len - 2];
    return computed == remote;
  }

  /// Which command a complete JBD response answers (0x03/0x04/...), or
  /// null if [buffer] isn't a complete, CRC-valid frame yet.
  static int? jbdResponseFunction(List<int> buffer) {
    if (!isCompleteJbdFrame(buffer)) return null;
    return buffer[1];
  }

  static BmsStatus? parseJbdBasicInfoFrame(List<int> buffer) {
    if (!isCompleteJbdFrame(buffer) || buffer[1] != jbdCommandBasicInfo) return null;
    final dataLen = buffer[3];
    final d = buffer.sublist(4, 4 + dataLen);
    if (d.length < 23) return null;

    int be16(int o) => (d[o] << 8) | d[o + 1];
    int sbe16(int o) {
      final v = be16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    try {
      final totalVoltage = be16(0) * 0.01;
      final currentA = sbe16(2) * 0.01;
      final balanceBitmask = (be16(12) << 16) | be16(14);
      final mosByte = d[20];
      final tempSensors = d.length > 22 ? d[22].clamp(0, 6) : 0;
      final t1 = tempSensors > 0 ? (be16(23) - 2731) * 0.1 : 0.0;
      final t2 = tempSensors > 1 ? (be16(25) - 2731) * 0.1 : 0.0;

      return BmsStatus(
        brand: BmsBrand.jbd,
        modelName: 'JBD/Xiaoxiang BMS',
        soc: d[19],
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: be16(4) * 0.01,
        nominalCapacityAh: be16(6) * 0.01,
        cycleCount: be16(8),
        // Not present in this frame -- zeroed rather than inheriting
        // BmsStatus's demo defaults.
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: const [],
        mosTemp: 0.0,
        t1Temp: t1,
        t2Temp: t2,
        chargeMosEnabled: (mosByte & 0x01) != 0,
        dischargeMosEnabled: (mosByte & 0x02) != 0,
        balanceEnabled: balanceBitmask > 0,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<CellInfo>? parseJbdCellInfoFrame(List<int> buffer) {
    if (!isCompleteJbdFrame(buffer) || buffer[1] != jbdCommandCellInfo) return null;
    final dataLen = buffer[3];
    if (dataLen < 2 || dataLen > 64 || dataLen % 2 != 0) return null;
    final d = buffer.sublist(4, 4 + dataLen);

    final cells = <CellInfo>[];
    final cellCount = (dataLen ~/ 2).clamp(0, 32);
    for (int i = 0; i < cellCount; i++) {
      final mv = (d[i * 2] << 8) | d[i * 2 + 1];
      if (mv <= 0) continue;
      cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
    }
    return cells;
  }

  /// Returns a copy of [status] with its cell list replaced. Used to merge
  /// a brand's separately-arriving cell-voltage frame into the most
  /// recent overall status frame (JBD splits these across two responses).
  static BmsStatus withCells(BmsStatus status, List<CellInfo> cells) => status.copyWith(cells: cells);

  // ===== ANT BMS =====
  // Verified against syssi/esphome-ant-bms (ant_bms_ble.cpp,
  // switch/__init__.py). Frame: 7E A1 [func] [addrLo addrHi] [value]
  // [crc16 lo hi] AA 55, crc = modbusCrc16(bytes[1..5]) -- 5 bytes
  // (func, addrLo, addrHi, value), NOT including the leading 7E A1.
  static const int antCommandStatus = 0x01;
  static const int antCommandWriteRegister = 0x51;
  static const int antFrameTypeStatus = 0x11;

  // [turnOnRegister, turnOffRegister] -- ANT uses two distinct addresses
  // per switch rather than a value written to one address.
  static const int antRegDischargeOn = 0x0003;
  static const int antRegDischargeOff = 0x0001;
  static const int antRegChargeOn = 0x0006;
  static const int antRegChargeOff = 0x0004;
  static const int antRegBalancerOn = 0x000D;
  static const int antRegBalancerOff = 0x000E;

  static Uint8List buildAntFrame(int function, int address, int value) {
    final frame = Uint8List(10);
    frame[0] = 0x7E;
    frame[1] = 0xA1;
    frame[2] = function;
    frame[3] = address & 0xFF;
    frame[4] = (address >> 8) & 0xFF;
    frame[5] = value & 0xFF;
    final crc = modbusCrc16(frame.sublist(1, 6));
    frame[6] = crc & 0xFF;
    frame[7] = (crc >> 8) & 0xFF;
    frame[8] = 0xAA;
    frame[9] = 0x55;
    return frame;
  }

  static Uint8List buildAntStatusRequest() => buildAntFrame(antCommandStatus, 0x0000, 0xBE);

  static Uint8List buildAntSwitchCommand(bool turnOn, {required int onRegister, required int offRegister}) {
    return buildAntFrame(antCommandWriteRegister, turnOn ? onRegister : offRegister, 0x00);
  }

  static int? _completeAntFrameLength(List<int> buffer) {
    if (buffer.length < 6) return null;
    if (buffer[0] != 0x7E || buffer[1] != 0xA1) return null;
    final dataLen = buffer[5];
    final frameLen = 6 + dataLen + 4;
    if (buffer.length < frameLen) return null;
    if (buffer[frameLen - 2] != 0xAA || buffer[frameLen - 1] != 0x55) return null;
    return frameLen;
  }

  static bool isCompleteAntFrame(List<int> buffer) {
    final len = _completeAntFrameLength(buffer);
    if (len == null) return false;
    final computed = modbusCrc16(buffer.sublist(1, len - 4));
    final remote = buffer[len - 4] | (buffer[len - 3] << 8);
    return computed == remote;
  }

  static BmsStatus? parseAntStatusFrame(List<int> data) {
    if (!isCompleteAntFrame(data) || data[2] != antFrameTypeStatus) return null;

    int le16(int o) => data[o] | (data[o + 1] << 8);
    int sle16(int o) {
      final v = le16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    int le32(int o) => (data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24)) & 0xFFFFFFFF;
    int sle32(int o) {
      final v = le32(o);
      return v >= 0x80000000 ? v - 0x100000000 : v;
    }

    try {
      final cellCount = data[9].clamp(0, 32);
      final tempSensors = data[8].clamp(0, 4);

      final cells = <CellInfo>[];
      for (int i = 0; i < cellCount; i++) {
        final mv = le16(i * 2 + 34);
        if (mv <= 0) continue;
        cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
      }

      int offset = cellCount * 2;
      final temps = <double>[];
      for (int i = 0; i < tempSensors; i++) {
        temps.add(sle16(i * 2 + 34 + offset).toDouble());
      }
      offset += tempSensors * 2;

      final mosTemp = sle16(34 + offset).toDouble();
      final totalVoltage = le16(38 + offset) * 0.01;
      final currentA = sle16(40 + offset) * 0.1;
      final soc = sle16(42 + offset);
      final chargeMosOn = data[46 + offset] == 0x01;
      final dischargeMosOn = data[47 + offset] == 0x01;
      final balancerOn = data[48 + offset] == 0x04;
      final nominalCapacityAh = le32(50 + offset) * 0.000001;
      final remainingCapacityAh = le32(54 + offset) * 0.000001;
      final totalCycleCapacityAh = le32(58 + offset) * 0.001;
      final power = sle32(62 + offset).toDouble();

      return BmsStatus(
        brand: BmsBrand.ant,
        modelName: 'ANT BMS',
        soc: soc.clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: power,
        remainingCapacityAh: remainingCapacityAh,
        nominalCapacityAh: nominalCapacityAh,
        // No distinct charge-cycle counter in this frame, only cumulative
        // Ah throughput (totalCycleCapacityAh) -- zeroed rather than
        // inheriting BmsStatus's demo default.
        cycleCount: 0,
        totalCycleCapacityAh: totalCycleCapacityAh,
        balanceCurrentA: 0.0,
        cells: cells,
        mosTemp: mosTemp,
        t1Temp: temps.isNotEmpty ? temps[0] : 0.0,
        t2Temp: temps.length > 1 ? temps[1] : 0.0,
        chargeMosEnabled: chargeMosOn,
        dischargeMosEnabled: dischargeMosOn,
        balanceEnabled: balancerOn,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Seplos Active Balancer =====
  // Verified against syssi/esphome-seplos-bms (seplos_bms_ble.cpp,
  // switch/__init__.py). Frame: 7E 10 00 46 [func] [lenHi lenLo]
  // [payload] [crc16 hi lo] 0D, crc = xmodemCrc16(bytes[1..]) covering
  // everything between the leading 0x7E and the crc bytes.
  static const int seplosCommandGetSingleMachineData = 0x61;
  static const int seplosCommandSetMosfetControl = 0xAA;

  static const int seplosSwitchBitDischarge = 0x01;
  static const int seplosSwitchBitCharge = 0x02;

  static Uint8List buildSeplosFrame(int function, List<int> payload) {
    final header = <int>[
      0x10, 0x00, 0x46, function,
      (payload.length >> 8) & 0xFF, payload.length & 0xFF,
      ...payload,
    ];
    final crc = xmodemCrc16(header);
    return Uint8List.fromList(<int>[0x7E, ...header, (crc >> 8) & 0xFF, crc & 0xFF, 0x0D]);
  }

  static Uint8List buildSeplosStatusRequest() => buildSeplosFrame(seplosCommandGetSingleMachineData, [0x00]);

  static Uint8List buildSeplosSwitchCommand(int switchBit, bool enable) {
    return buildSeplosFrame(seplosCommandSetMosfetControl, [switchBit, enable ? 0x01 : 0x00]);
  }

  static int? _completeSeplosFrameLength(List<int> buffer) {
    if (buffer.length < 7) return null;
    if (buffer[0] != 0x7E) return null;
    final dataLen = (buffer[5] << 8) | buffer[6];
    final frameLen = 7 + dataLen + 2 + 1;
    if (buffer.length < frameLen) return null;
    if (buffer[frameLen - 1] != 0x0D) return null;
    return frameLen;
  }

  static bool isCompleteSeplosFrame(List<int> buffer) {
    final len = _completeSeplosFrameLength(buffer);
    if (len == null) return false;
    final computed = xmodemCrc16(buffer.sublist(1, len - 3));
    final remote = (buffer[len - 3] << 8) | buffer[len - 2];
    return computed == remote;
  }

  static BmsStatus? parseSeplosSingleMachineFrame(List<int> data) {
    if (!isCompleteSeplosFrame(data) || data[3] != seplosCommandGetSingleMachineData) return null;
    if (data.length < 60) return null;

    int be16(int o) => (data[o] << 8) | data[o + 1];
    int sbe16(int o) {
      final v = be16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    try {
      final cellCount = data[9].clamp(0, 24);
      final cells = <CellInfo>[];
      for (int i = 0; i < cellCount; i++) {
        final mv = be16(10 + i * 2);
        if (mv <= 0) continue;
        cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
      }

      final tempBlockOffset = 10 + cellCount * 2;
      if (data.length <= tempBlockOffset) return null;
      final temperatures = data[tempBlockOffset];
      final cellTemps = temperatures > 2 ? temperatures - 2 : 0;

      double t1 = 0.0, t2 = 0.0;
      if (cellTemps > 0) t1 = (be16(tempBlockOffset + 1) - 2731) * 0.1;
      if (cellTemps > 1) t2 = (be16(tempBlockOffset + 3) - 2731) * 0.1;
      final mosTemp = (be16(tempBlockOffset + 1 + cellTemps * 2 + 2) - 2731) * 0.1;

      final statusOffset = 10 + cellCount * 2 + 1 + temperatures * 2;
      if (data.length < statusOffset + 18) return null;

      final currentA = sbe16(statusOffset) * 0.01;
      final totalVoltage = be16(statusOffset + 2) * 0.01;
      final remainingCapacityAh = be16(statusOffset + 4) * 0.01;
      final nominalCapacityAh = be16(statusOffset + 11) * 0.01;
      final soc = (be16(statusOffset + 9) * 0.1).round();
      final cycleCount = be16(statusOffset + 13);

      final protectionOffset = statusOffset + 19 + cellCount + temperatures;
      bool chargeMosEnabled = false;
      bool dischargeMosEnabled = false;
      if (data.length > protectionOffset + 3) {
        final switchStatus = data[protectionOffset + 3];
        dischargeMosEnabled = (switchStatus & 0x01) != 0;
        chargeMosEnabled = (switchStatus & 0x02) != 0;
      }

      return BmsStatus(
        brand: BmsBrand.seplos,
        modelName: 'Seplos Active Balancer',
        soc: soc.clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: remainingCapacityAh,
        nominalCapacityAh: nominalCapacityAh,
        cycleCount: cycleCount,
        // Not present in this frame -- zeroed rather than inheriting
        // BmsStatus's demo defaults.
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: cells,
        mosTemp: mosTemp,
        t1Temp: t1,
        t2Temp: t2,
        chargeMosEnabled: chargeMosEnabled,
        dischargeMosEnabled: dischargeMosEnabled,
        // No balancer status bit in this frame -- explicitly false rather
        // than inheriting BmsStatus's demo default of true.
        balanceEnabled: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Tianpower BMS =====
  // Verified against syssi/esphome-tianpower-bms. Fixed 20-byte frames, no
  // checksum -- only 0x55 start / 0xAA end markers. Monitoring only; no
  // switch/control support exists upstream.
  static const String tianpowerServiceUuid = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String tianpowerNotifyCharUuid = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String tianpowerControlCharUuid = "0000ff02-0000-1000-8000-00805f9b34fb";

  static const int tianpowerFrameTypeStatus = 0x83;

  static Uint8List buildTianpowerCommand(int frameType) => Uint8List.fromList([0x55, 0x04, frameType, 0xAA]);

  static Uint8List buildTianpowerStatusRequest() => buildTianpowerCommand(tianpowerFrameTypeStatus);

  static bool isCompleteTianpowerFrame(List<int> buffer) {
    return buffer.length == 20 && buffer[0] == 0x55 && buffer[19] == 0xAA;
  }

  static BmsStatus? parseTianpowerStatusFrame(List<int> data) {
    if (!isCompleteTianpowerFrame(data) || data[2] != tianpowerFrameTypeStatus) return null;

    int be16(int o) => (data[o] << 8) | data[o + 1];
    int sbe16(int o) {
      final v = be16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    try {
      final totalVoltage = be16(5) * 0.01;
      final currentA = sbe16(13) * 0.01;

      return BmsStatus(
        brand: BmsBrand.tianpower,
        modelName: 'Tianpower BMS',
        soc: be16(3).clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        // Capacity/cycle data lives in a separate GeneralInfo frame this
        // brand doesn't request yet -- zeroed rather than inheriting
        // BmsStatus's demo defaults.
        remainingCapacityAh: 0.0,
        nominalCapacityAh: 0.0,
        cycleCount: 0,
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: const [],
        mosTemp: sbe16(11) * 0.1,
        t1Temp: sbe16(7) * 0.1,
        t2Temp: sbe16(9) * 0.1,
        // MOSFET/balancer status lives in separate frames (0x85) this
        // brand doesn't request yet -- explicitly false rather than
        // inheriting BmsStatus's demo default of true (which would show
        // fake "ON" indicators the app never actually confirmed).
        chargeMosEnabled: false,
        dischargeMosEnabled: false,
        balanceEnabled: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Basen BMS =====
  // Verified against syssi/esphome-basen-bms. Frame: [SOF] [addr] [func]
  // [len] [payload] [crc lo hi] 0D 0A. SOF = 0x3A (poll request) or 0x3B
  // (write / unsolicited status push); crc = plain 16-bit sum of
  // bytes[1 .. 3+len] (addr+func+len+payload).
  static const String basenServiceUuid = "0000fa00-0000-1000-8000-00805f9b34fb";
  static const String basenNotifyCharUuid = "0000fa01-0000-1000-8000-00805f9b34fb";
  static const String basenControlCharUuid = "0000fa02-0000-1000-8000-00805f9b34fb";

  static const int basenAddress = 0x16;
  static const int basenFrameTypeWrite = 0xEB;
  static const int basenFrameTypeStatus = 0x2A;
  static const int basenRegChargeDischarge = 0x011D;
  static const int basenBitCharge = 0;
  static const int basenBitDischarge = 1;

  static Uint8List buildBasenFrame(int startOfFrame, int function, List<int> data) {
    final frame = Uint8List(data.length + 8);
    frame[0] = startOfFrame;
    frame[1] = basenAddress;
    frame[2] = function;
    frame[3] = data.length;
    for (int i = 0; i < data.length; i++) {
      frame[4 + i] = data[i];
    }
    int sum = 0;
    for (int i = 1; i < 4 + data.length; i++) {
      sum += frame[i];
    }
    frame[4 + data.length] = sum & 0xFF;
    frame[5 + data.length] = (sum >> 8) & 0xFF;
    frame[6 + data.length] = 0x0D;
    frame[7 + data.length] = 0x0A;
    return frame;
  }

  static Uint8List buildBasenStatusRequest() => buildBasenFrame(0x3A, basenFrameTypeStatus, const []);

  /// Sets one bit of the shared charge/discharge holding register.
  /// [currentMosfetStatus] must be the last-known combined status byte
  /// (bit0=charge, bit1=discharge — reconstructed the same way
  /// esphome-basen-bms does: `(charge?1:0)|(discharge?2:0)`) so the other
  /// switch's state isn't clobbered — Basen has no independent
  /// single-switch write.
  static Uint8List buildBasenSwitchCommand(int currentMosfetStatus, int bit, bool enable) {
    final value = enable ? (currentMosfetStatus | (1 << bit)) : (currentMosfetStatus & ~(1 << bit));
    final data = [0x86, basenRegChargeDischarge & 0xFF, (basenRegChargeDischarge >> 8) & 0xFF, value & 0xFF];
    return buildBasenFrame(0x3B, basenFrameTypeWrite, data);
  }

  static int? _completeBasenFrameLength(List<int> buffer) {
    if (buffer.length < 8) return null;
    if (buffer[0] != 0x3A && buffer[0] != 0x3B) return null;
    final dataLen = buffer[3];
    final frameLen = 4 + dataLen + 4;
    if (buffer.length < frameLen) return null;
    if (buffer[frameLen - 2] != 0x0D || buffer[frameLen - 1] != 0x0A) return null;
    return frameLen;
  }

  static bool isCompleteBasenFrame(List<int> buffer) {
    final len = _completeBasenFrameLength(buffer);
    if (len == null) return false;
    final dataLen = buffer[3];
    int sum = 0;
    for (int i = 1; i < 4 + dataLen; i++) {
      sum += buffer[i];
    }
    final remote = buffer[len - 4] | (buffer[len - 3] << 8);
    return (sum & 0xFFFF) == remote;
  }

  static BmsStatus? parseBasenStatusFrame(List<int> data) {
    if (!isCompleteBasenFrame(data) || data[2] != basenFrameTypeStatus) return null;

    int le32(int o) => (data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24)) & 0xFFFFFFFF;
    int sle32(int o) {
      final v = le32(o);
      return v >= 0x80000000 ? v - 0x100000000 : v;
    }

    try {
      final currentA = sle32(4) * 0.001;
      final totalVoltage = le32(8) * 0.001;
      final chargeMos = (data[20] & (1 << 7)) != 0;
      final dischargeMos = (data[21] & (1 << 7)) != 0;

      return BmsStatus(
        brand: BmsBrand.basen,
        modelName: 'Basen BMS',
        soc: data[24].clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: le32(16) * 0.001,
        // Nominal capacity/cycle count live in a separate GeneralInfo
        // frame this brand doesn't request yet -- zeroed rather than
        // inheriting BmsStatus's demo defaults.
        nominalCapacityAh: 0.0,
        cycleCount: 0,
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: const [],
        mosTemp: 0.0,
        t1Temp: data[12].toSigned(8).toDouble(),
        t2Temp: data[13].toSigned(8).toDouble(),
        chargeMosEnabled: chargeMos,
        dischargeMosEnabled: dischargeMos,
        // No balancer status bit found in this frame -- explicitly false
        // rather than inheriting BmsStatus's demo default of true.
        balanceEnabled: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== KS48100 BMS =====
  // Verified against syssi/esphome-ks-bms. Frame: 7B [type] [len]
  // [payload] 7D, no checksum -- validated by exact length only
  // (frame.length == data[2] + 4). Each BLE notification is treated as
  // one complete frame, matching upstream (which doesn't reassemble
  // fragments for this brand).
  static const String ksServiceUuid = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String ksNotifyCharUuid = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String ksControlCharUuid = "0000ff02-0000-1000-8000-00805f9b34fb";

  static const int ksFrameTypeStatus = 0x01;
  static const int ksFrameTypeCellVoltages = 0x02;
  static const int ksRegCharge = 0x1D;
  static const int ksRegDischarge = 0x1E;

  static Uint8List buildKsCommand(int frameType) => Uint8List.fromList([0x7B, frameType, 0x00, 0x7D]);
  static Uint8List buildKsStatusRequest() => buildKsCommand(ksFrameTypeStatus);
  static Uint8List buildKsCellVoltagesRequest() => buildKsCommand(ksFrameTypeCellVoltages);

  static Uint8List buildKsSwitchCommand(int register, bool enable) {
    return Uint8List.fromList([0x7B, register, 0x02, 0x00, enable ? 0x01 : 0x00, 0x7D]);
  }

  static const int ksFrameTypeBasicConfig = 0x04;
  static const int ksFrameTypeVoltageProtection = 0x05;
  static const int ksFrameTypeTempProtection = 0x06;
  static const int ksFrameTypeCurrentProtection = 0x07;

  /// All four KS config frames in one request list — the BMS answers each
  /// with a config frame bearing the same frame type (0x04..0x07), which
  /// [parseKsSettingsFrame] maps back to registers.
  static List<Uint8List> buildKsSettingsRequests() => [
    buildKsCommand(ksFrameTypeBasicConfig),
    buildKsCommand(ksFrameTypeVoltageProtection),
    buildKsCommand(ksFrameTypeTempProtection),
    buildKsCommand(ksFrameTypeCurrentProtection),
  ];

  /// Builds a KS holding-register write: `7B [reg] 02 [hi] [lo] 7D`, big-
  /// endian u16, written with NO_RSP exactly like syssi's
  /// `KsBmsBle::write_register` (ks_bms_ble.cpp:166).
  static Uint8List buildKsWriteCommand(int register, int raw) {
    return Uint8List.fromList([
      0x7B,
      register & 0xFF,
      0x02,
      (raw >> 8) & 0xFF,
      raw & 0xFF,
      0x7D,
    ]);
  }

  /// If [data] is a complete KS config frame (one of 0x04..0x07), returns a
  /// map of holding register -> raw big-endian u16. Byte index = 3 + offset*2
  /// where offset = register - frame_base, frame_base maps 0x04->0x10,
  /// 0x05->0x20, 0x06->0x30, 0x07->0x40 (syssi's decoders at
  /// ks_bms_ble.cpp:431/481/510/546 read exactly these offsets). The value
  /// is left raw so the caller applies the schema's (raw-offset)/factor.
  /// Returns null if the frame is not a config frame or is malformed.
  static Map<int, int>? parseKsSettingsFrame(List<int> data) {
    const bases = {0x04: 0x10, 0x05: 0x20, 0x06: 0x30, 0x07: 0x40};
    if (!isCompleteKsFrame(data)) return null;
    final frameType = data[1];
    final base = bases[frameType];
    if (base == null) return null;

    final regs = <int, int>{};
    final byteIndex = 3;

    final valueBytes = data[2];
    for (int i = 0; i + 1 < valueBytes; i += 2) {
      regs[base + (i >> 1)] = (data[byteIndex + i] << 8) | data[byteIndex + i + 1];
    }
    return regs;
  }

  static bool isCompleteKsFrame(List<int> buffer) {
    if (buffer.length < 4) return false;
    if (buffer[0] != 0x7B || buffer.last != 0x7D) return false;
    return buffer.length == buffer[2] + 4;
  }

  static BmsStatus? parseKsStatusFrame(List<int> data) {
    if (!isCompleteKsFrame(data) || data[1] != ksFrameTypeStatus) return null;

    int be16(int o) => (data[o] << 8) | data[o + 1];
    int sbe16(int o) {
      final v = be16(o);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    try {
      final totalVoltage = be16(5) * 0.01;
      final currentA = sbe16(13) * 0.01;
      final fetStatus = be16(29);

      return BmsStatus(
        brand: BmsBrand.ks,
        modelName: 'KS48100 BMS',
        soc: be16(3).clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: be16(15) * 0.01,
        nominalCapacityAh: be16(19) * 0.01,
        cycleCount: be16(23),
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: const [],
        mosTemp: sbe16(11) * 0.1,
        t1Temp: sbe16(7) * 0.1,
        t2Temp: sbe16(9) * 0.1,
        // FET control status bitmask: bit0/1=balancer charging/
        // discharging, bit2=charging, bit3=discharging (esphome checks
        // these as literal mask values 1/2/4/8).
        chargeMosEnabled: (fetStatus & 0x04) != 0,
        dischargeMosEnabled: (fetStatus & 0x08) != 0,
        balanceEnabled: (fetStatus & 0x03) != 0,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<CellInfo>? parseKsCellVoltagesFrame(List<int> data) {
    if (!isCompleteKsFrame(data) || data[1] != ksFrameTypeCellVoltages) return null;
    int be16(int o) => (data[o] << 8) | data[o + 1];
    final cellCount = data[3].clamp(0, 24);
    final cells = <CellInfo>[];
    for (int i = 0; i < cellCount; i++) {
      final mv = be16((i * 2) + 4);
      if (mv <= 0) continue;
      cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
    }
    return cells;
  }

  // ===== Topband BMS (v1) =====
  // Verified against syssi/esphome-topband-bms. Passive/receive-only —
  // no request needs to be sent, the device streams status automatically
  // once notifications are enabled. Wire format: 1 raw SOF byte (0x5E,
  // 0x83, or 0xB0) followed by 112 ASCII hex characters (56 bytes) = 113
  // bytes total; hex-decode to the real 56-byte binary frame, whose last
  // 2 bytes are a big-endian 16-bit sum-checksum of the first 54.
  static const String topbandServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String topbandNotifyCharUuid = "0000ffe4-0000-1000-8000-00805f9b34fb";

  static const int _topbandAsciiFrameSize = 113;

  static bool _isTopbandSof(int b) => b == 0x5E || b == 0x83 || b == 0xB0;

  static bool _isHexDigit(int b) =>
      (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66);

  static int _asciiHexToByte(int hi, int lo) {
    int nibble(int c) => c <= 0x39 ? c - 0x30 : (c & 0x7) + 9;
    return (nibble(hi) << 4) + nibble(lo);
  }

  static bool isCompleteTopbandFrame(List<int> buffer) {
    if (buffer.length != _topbandAsciiFrameSize) return false;
    if (!_isTopbandSof(buffer[0])) return false;
    for (int i = 1; i < buffer.length; i++) {
      if (!_isHexDigit(buffer[i])) return false;
    }
    return true;
  }

  static BmsStatus? parseTopbandFrame(List<int> buffer) {
    if (!isCompleteTopbandFrame(buffer)) return null;

    final d = List<int>.generate(56, (i) => _asciiHexToByte(buffer[1 + 2 * i], buffer[2 + 2 * i]));

    int sum = 0;
    for (int i = 0; i < 54; i++) {
      sum += d[i];
    }
    final storedCrc = (d[54] << 8) | d[55];
    if ((sum & 0xFFFF) != storedCrc) return null;

    int le16(int o) => d[o] | (d[o + 1] << 8);
    int le32(int o) => (d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)) & 0xFFFFFFFF;
    int sle32(int o) {
      final v = le32(o);
      return v >= 0x80000000 ? v - 0x100000000 : v;
    }

    try {
      final totalVoltage = le32(0) * 0.001;
      final currentA = sle32(4) * 0.001;

      final cells = <CellInfo>[];
      for (int i = 0; i < 16; i++) {
        final mv = le16(22 + i * 2);
        if (mv <= 0) continue;
        cells.add(CellInfo(index: i + 1, voltage: mv * 0.001));
      }

      return BmsStatus(
        brand: BmsBrand.topband,
        modelName: 'Topband BMS',
        soc: le16(14).clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        remainingCapacityAh: le32(8) * 0.001,
        nominalCapacityAh: 0.0,
        cycleCount: le16(12),
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: cells,
        mosTemp: 0.0,
        t1Temp: le16(16) * 0.1 - 273.1,
        t2Temp: 0.0,
        // No MOSFET/balancer hardware-status bits in this frame (only a
        // charging/discharging state derived from current sign, already
        // reflected via currentA/chargeState) -- explicitly false rather
        // than inheriting BmsStatus's demo default of true.
        chargeMosEnabled: false,
        dischargeMosEnabled: false,
        balanceEnabled: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Lolan BMS =====
  // Verified against syssi/esphome-lolan-bms. Request: [funcHi funcLo]
  // [password, 4 bytes BE] (6 bytes, no checksum) -- the same mechanism
  // is reused for switch writes with distinct turn-on/turn-off function
  // codes. Response: [frameType] 0x00 [payload...]; status/cell-info
  // responses aren't checksummed in the reference implementation (only
  // the separate Settings frame is). Values are IEEE-754 float32,
  // big-endian.
  static const String lolanServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String lolanNotifyCharUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";
  static const String lolanControlCharUuid = "0000ffe2-0000-1000-8000-00805f9b34fb";

  static const int lolanCommandReqStatus = 0xc565;
  static const int lolanCommandReqCellInfo = 0x5b65;
  static const int lolanFrameTypeStatus = 0x01;
  static const int lolanFrameTypeCellInfo = 0x02;
  static const int lolanDefaultPassword = 12345678;
  static const int lolanCommandChargeOn = 0xD888;
  static const int lolanCommandChargeOff = 0xD900;
  static const int lolanCommandDischargeOn = 0x8555;
  static const int lolanCommandDischargeOff = 0x8600;

  static Uint8List buildLolanCommand(int function, {int password = lolanDefaultPassword}) {
    final frame = Uint8List(6);
    frame[0] = (function >> 8) & 0xFF;
    frame[1] = function & 0xFF;
    frame[2] = (password >> 24) & 0xFF;
    frame[3] = (password >> 16) & 0xFF;
    frame[4] = (password >> 8) & 0xFF;
    frame[5] = password & 0xFF;
    return frame;
  }

  static double _beFloat32(List<int> d, int o) {
    final bytes = Uint8List.fromList([d[o], d[o + 1], d[o + 2], d[o + 3]]);
    return ByteData.sublistView(bytes).getFloat32(0, Endian.big);
  }

  static int _lolanU16(List<int> d, int o) => (d[o] << 8) | d[o + 1];

  static bool isCompleteLolanFrame(List<int> buffer) => buffer.length >= 40;

  static BmsStatus? parseLolanStatusFrame(List<int> data) {
    if (!isCompleteLolanFrame(data) || data[0] != lolanFrameTypeStatus) return null;
    try {
      final totalVoltage = _beFloat32(data, 4);
      final negativeCurrent = _beFloat32(data, 8);
      final positiveCurrent = _beFloat32(data, 12);
      final currentA = negativeCurrent > positiveCurrent ? -negativeCurrent : positiveCurrent;

      return BmsStatus(
        brand: BmsBrand.lolan,
        modelName: 'Lolan BMS',
        soc: _lolanU16(data, 38).clamp(0, 100),
        totalVoltage: totalVoltage,
        currentA: currentA,
        powerW: totalVoltage * currentA,
        // This frame only reports cumulative lifetime charged/discharged
        // Ah, not remaining-capacity-in-tank or a rated nominal capacity
        // -- zeroed rather than showing a misleading substitute number.
        remainingCapacityAh: 0.0,
        nominalCapacityAh: 0.0,
        cycleCount: _lolanU16(data, 36),
        totalCycleCapacityAh: 0.0,
        balanceCurrentA: 0.0,
        cells: const [],
        mosTemp: 0.0,
        t1Temp: _beFloat32(data, 16),
        t2Temp: _beFloat32(data, 20),
        chargeMosEnabled: (data[2] & 0x02) != 0,
        dischargeMosEnabled: (data[2] & 0x01) != 0,
        // No balancer status bit in this frame -- explicitly false rather
        // than inheriting BmsStatus's demo default of true.
        balanceEnabled: false,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<CellInfo>? parseLolanCellInfoFrame(List<int> data) {
    if (!isCompleteLolanFrame(data) || data[0] != lolanFrameTypeCellInfo) return null;
    try {
      final cellCount = data[2].clamp(0, 16);
      final cells = <CellInfo>[];
      for (int i = 0; i < cellCount; i++) {
        final v = _beFloat32(data, (i * 4) + 24);
        if (v <= 0) continue;
        cells.add(CellInfo(index: i + 1, voltage: v));
      }
      return cells;
    } catch (_) {
      return null;
    }
  }
}
