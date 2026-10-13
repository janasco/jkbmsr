#include "Jk02Decoder.h"

#include <string.h>

namespace jkbmsr {

namespace {

uint16_t readU16Le(const uint8_t* p) {
  return static_cast<uint16_t>(p[0] | (static_cast<uint16_t>(p[1]) << 8));
}

uint32_t readU32Le(const uint8_t* p) {
  return static_cast<uint32_t>(readU16Le(p)) | (static_cast<uint32_t>(readU16Le(p + 2)) << 16);
}

String readString(const uint8_t* p, size_t maxLength) {
  char buffer[32] = {};
  const size_t length = maxLength < sizeof(buffer) - 1 ? maxLength : sizeof(buffer) - 1;
  memcpy(buffer, p, length);
  return String(buffer);
}

// "11.XW" / "V11.2" style hardware versions: the numeric major decides the
// frame layout (>= 11 means the 32-cell variant).
bool hardwareVersionIs32s(const String& hardwareVersion) {
  const char* text = hardwareVersion.c_str();
  while (*text != '\0' && (*text < '0' || *text > '9')) {
    ++text;
  }
  int major = 0;
  while (*text >= '0' && *text <= '9') {
    major = major * 10 + (*text - '0');
    ++text;
  }
  return major >= 11;
}

}  // namespace

uint8_t jk02Checksum(const uint8_t* data, size_t length) {
  uint8_t checksum = 0;
  for (size_t index = 0; index < length; ++index) {
    checksum += data[index];
  }
  return checksum;
}

String jk02FrameToHex(const uint8_t* frame, size_t length) {
  static const char kHexDigits[] = "0123456789abcdef";
  String out;
  if (frame == nullptr) {
    return out;
  }
  out.reserve(static_cast<unsigned int>(length * 2));
  for (size_t index = 0; index < length; ++index) {
    out += kHexDigits[(frame[index] >> 4) & 0x0F];
    out += kHexDigits[frame[index] & 0x0F];
  }
  return out;
}

bool jk02FrameValid(const uint8_t* frame, size_t length) {
  if (frame == nullptr || length < kJk02FrameSize) {
    return false;
  }
  if (frame[0] != 0x55 || frame[1] != 0xAA || frame[2] != 0xEB || frame[3] != 0x90) {
    return false;
  }
  return jk02Checksum(frame, kJk02FrameSize - 1) == frame[kJk02FrameSize - 1];
}

Jk02FrameType jk02FrameTypeOf(const uint8_t* frame, size_t length) {
  if (frame == nullptr || length < 5) {
    return Jk02FrameType::kUnknown;
  }
  switch (frame[4]) {
    case 0x01:
      return Jk02FrameType::kSettings;
    case 0x02:
      return Jk02FrameType::kCellInfo;
    case 0x03:
      return Jk02FrameType::kDeviceInfo;
    default:
      return Jk02FrameType::kUnknown;
  }
}

bool decodeJk02DeviceInfo(const uint8_t* frame, size_t length, Jk02DeviceInfo& out) {
  out = Jk02DeviceInfo();
  if (!jk02FrameValid(frame, length) ||
      jk02FrameTypeOf(frame, length) != Jk02FrameType::kDeviceInfo) {
    return false;
  }
  out.vendorId = readString(frame + 6, 16);
  out.hardwareVersion = readString(frame + 22, 8);
  out.softwareVersion = readString(frame + 30, 8);
  out.deviceName = readString(frame + 46, 16);
  out.is32s = hardwareVersionIs32s(out.hardwareVersion);
  out.valid = true;
  return true;
}

bool decodeJk02CellInfo(const uint8_t* frame, size_t length, bool is32s, BatteryTelemetry& out) {
  if (!jk02FrameValid(frame, length) ||
      jk02FrameTypeOf(frame, length) != Jk02FrameType::kCellInfo) {
    return false;
  }

  // First-half offsets shift by 16 bytes on the 32-cell layout, second-half
  // offsets by 32.
  const size_t off = is32s ? 16 : 0;
  const size_t off2 = off * 2;
  const uint8_t cellSlots = is32s ? 32 : 24;
  // Wire (balance-lead) resistance array immediately follows the cell
  // voltage array, at a fixed +10-byte gap after it on the 24s layout
  // (offset 64 = 6 + 24*2 + 10) — confirmed against a real 24s capture
  // (test_decode_24s_real_capture) and against syssi/esphome-jk-bms's
  // documented byte layout (offset 64, scale 0.001 Ohm/count). The 32s
  // offset (80 = 64 + off) applies the same +off shift used by every other
  // field between the cell array and packVoltage; it matches
  // syssi/esphome-jk-bms' jk_bms_ble.cpp (`i*2 + 64 + offset`, offset = 16
  // for JK02_32S) and a hardware-validated JK02_32S offset table (offset 80,
  // scale 0.001 Ohm/count). kCellInfo32s is synthetic, so the 32s value is
  // corroborated by those references rather than by a capture we took; a raw
  // 32s frame dump would close that last gap. A misread layout changes decoded
  // *values* (cell voltages, temperatures) — it does not, on its own, stop a
  // sample from being produced, so do not "correct" these on a hunch.
  const size_t wireResistanceBase = 64 + off;

  BatteryTelemetry parsed;
  parsed.source = "ble";
  parsed.minCellVoltage = 100.0f;
  parsed.maxCellVoltage = -100.0f;
  uint8_t enabledCells = 0;
  uint8_t highestCell = 0;
  for (uint8_t cell = 0; cell < cellSlots && cell < kMaxCellCount; ++cell) {
    const float voltage = static_cast<float>(readU16Le(frame + 6 + cell * 2)) * 0.001f;
    parsed.cellVoltages[cell] = voltage;
    parsed.wireResistanceOhms[cell] = static_cast<float>(readU16Le(frame + wireResistanceBase + cell * 2)) * 0.001f;
    if (voltage <= 0.0f) {
      continue;
    }
    enabledCells += 1;
    highestCell = cell + 1;
    parsed.avgCellVoltage += voltage;
    if (voltage < parsed.minCellVoltage) {
      parsed.minCellVoltage = voltage;
      parsed.minVoltageCell = cell + 1;
    }
    if (voltage > parsed.maxCellVoltage) {
      parsed.maxCellVoltage = voltage;
      parsed.maxVoltageCell = cell + 1;
    }
  }
  if (enabledCells == 0) {
    // Every cell slot read 0 V. On the 24-cell layout this stays a hard
    // reject: that path is proven working and is deliberately unchanged. On
    // the 32-cell layout it is a valid frame that must not be discarded — the
    // reference family (syssi/esphome-jk-bms) still publishes the pack-level
    // fields in this state, and a real 32S JK-PB2A16S30P that reports no cell
    // voltage (unpopulated/bench pack, or a transient while balancing)
    // otherwise produced pure silence: heartbeats only, never a decoded
    // sample. Carry the cells as an explicit empty set (cellCount stays 0)
    // and zero the derived values rather than leaving the 100/-100 scan
    // sentinels, so nothing downstream sees a nonsense min/max or a
    // divide-by-zero.
    if (!is32s) {
      return false;
    }
    parsed.minCellVoltage = 0.0f;
    parsed.maxCellVoltage = 0.0f;
    parsed.avgCellVoltage = 0.0f;
    parsed.deltaCellVoltage = 0.0f;
  } else {
    parsed.cellCount = highestCell;
    parsed.avgCellVoltage /= enabledCells;
    parsed.deltaCellVoltage = parsed.maxCellVoltage - parsed.minCellVoltage;
  }

  parsed.packVoltage = static_cast<float>(readU32Le(frame + 118 + off2)) * 0.001f;
  // Positive current = charging, matching the JK-BMS convention.
  parsed.packCurrent =
      static_cast<float>(static_cast<int32_t>(readU32Le(frame + 126 + off2))) * 0.001f;
  parsed.power = parsed.packVoltage * parsed.packCurrent;
  parsed.temperature1 =
      static_cast<float>(static_cast<int16_t>(readU16Le(frame + 130 + off2))) * 0.1f;
  parsed.temperature2 =
      static_cast<float>(static_cast<int16_t>(readU16Le(frame + 132 + off2))) * 0.1f;

  if (is32s) {
    parsed.mosfetTemperature =
        static_cast<float>(static_cast<int16_t>(readU16Le(frame + 112 + off2))) * 0.1f;
    parsed.errorsBitmask = readU32Le(frame + 134 + off2);
  } else {
    parsed.mosfetTemperature =
        static_cast<float>(static_cast<int16_t>(readU16Le(frame + 134 + off2))) * 0.1f;
    parsed.errorsBitmask = readU16Le(frame + 136 + off2);
  }

  parsed.balancingCurrent =
      static_cast<float>(static_cast<int16_t>(readU16Le(frame + 138 + off2))) * 0.001f;
  parsed.balancingActive = frame[140 + off2] != 0x00;
  parsed.stateOfCharge = static_cast<float>(frame[141 + off2]);
  parsed.remainingCapacityAh = static_cast<float>(readU32Le(frame + 142 + off2)) * 0.001f;
  parsed.fullCapacityAh = static_cast<float>(readU32Le(frame + 146 + off2)) * 0.001f;
  parsed.cycleCount = readU32Le(frame + 150 + off2);
  parsed.cycleCapacityAh = static_cast<float>(readU32Le(frame + 154 + off2)) * 0.001f;
  parsed.stateOfHealth = frame[158 + off2];
  parsed.chargingEnabled = frame[166 + off2] != 0x00;
  parsed.dischargingEnabled = frame[167 + off2] != 0x00;

  parsed.valid = true;
  parsed.capturedAtMs = out.capturedAtMs;
  out = parsed;
  return true;
}

}  // namespace jkbmsr
