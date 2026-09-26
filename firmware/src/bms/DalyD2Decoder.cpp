#include "DalyD2Decoder.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0xD2;
constexpr uint8_t kFunctionRead = 0x03;
// Every response's byte 1 is this fixed marker, not an echoed function code.
constexpr uint8_t kResponseMarker = 0x03;
constexpr uint16_t kStatusAddress = 0x0000;
// Response sizes: 3-byte header + (registers * 2) data bytes + 2-byte CRC.
constexpr size_t kStatusFrameLen62 = 3 + 62 * 2 + 2;
constexpr size_t kStatusFrameLen80 = 3 + 80 * 2 + 2;

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint64_t readU64(const uint8_t* p) {
  uint64_t value = 0;
  for (int i = 0; i < 8; ++i) {
    value = (value << 8) | p[i];
  }
  return value;
}

}  // namespace

uint16_t DalyD2Decoder::crc16Modbus(const uint8_t* data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; ++bit) {
      if (crc & 0x0001) {
        crc = static_cast<uint16_t>((crc >> 1) ^ 0xA001);
      } else {
        crc = static_cast<uint16_t>(crc >> 1);
      }
    }
  }
  return crc;
}

void DalyD2Decoder::buildStatusRequest(uint8_t frame[8]) {
  frame[0] = kFrameStart;
  frame[1] = kFunctionRead;
  frame[2] = static_cast<uint8_t>(kStatusAddress >> 8);
  frame[3] = static_cast<uint8_t>(kStatusAddress);
  frame[4] = static_cast<uint8_t>(kStatusRegisterCount >> 8);
  frame[5] = static_cast<uint8_t>(kStatusRegisterCount);
  const uint16_t crc = crc16Modbus(frame, 6);
  frame[6] = static_cast<uint8_t>(crc);       // low byte first
  frame[7] = static_cast<uint8_t>(crc >> 8);
}

bool DalyD2Decoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || (length != kStatusFrameLen62 && length != kStatusFrameLen80)) {
    return false;
  }
  if (frame[0] != kFrameStart || frame[1] != kResponseMarker) {
    return false;
  }
  const uint16_t computedCrc = crc16Modbus(frame, length - 2);
  const uint16_t remoteCrc = static_cast<uint16_t>(frame[length - 2] | (frame[length - 1] << 8));
  if (computedCrc != remoteCrc) {
    return false;
  }

  // d is the first data byte; every offset below matches the upstream
  // frame-layout comments (absolute byte position in the full frame minus
  // 3 for the header).
  const uint8_t* d = frame + 3;

  telemetry.source = "ble";

  // Cell voltages: cell count is read from the low byte of the offset-101
  // field (the high byte is always 0 for any realistic pack size) — same
  // simplification the reference implementation uses for its loop bound.
  const uint8_t cellCount = d[102 - 3] > kMaxCellCount ? kMaxCellCount : d[102 - 3];
  if (cellCount == 0) {
    return false;
  }
  telemetry.cellCount = cellCount;
  telemetry.minCellVoltage = 100.0f;
  telemetry.maxCellVoltage = -100.0f;
  float sum = 0.0f;
  for (uint8_t cell = 0; cell < cellCount; ++cell) {
    // Cell 1 at absolute offset 3 (== d[0]), cell 2 at offset 5, etc.
    const float voltage = static_cast<float>(readU16(d + cell * 2)) * 0.001f;
    telemetry.cellVoltages[cell] = voltage;
    sum += voltage;
    if (voltage < telemetry.minCellVoltage) {
      telemetry.minCellVoltage = voltage;
      telemetry.minVoltageCell = static_cast<uint8_t>(cell + 1);
    }
    if (voltage > telemetry.maxCellVoltage) {
      telemetry.maxCellVoltage = voltage;
      telemetry.maxVoltageCell = static_cast<uint8_t>(cell + 1);
    }
  }
  // Computed from the cell array rather than trusting the separate
  // avg/delta registers (offsets 113/115) — consistent with every other
  // parser in this codebase, and can't disagree with the cells actually
  // decoded above.
  telemetry.avgCellVoltage = sum / cellCount;
  telemetry.deltaCellVoltage = telemetry.maxCellVoltage - telemetry.minCellVoltage;

  // Temperatures: sensor count is the low byte of the offset-103 field.
  const uint8_t temperatureSensors = d[104 - 3];
  telemetry.temperatureSensorCount = temperatureSensors;
  if (temperatureSensors > 0) {
    telemetry.temperature1 = static_cast<float>(readU16(d + 67 - 3)) - 40.0f;
  }
  if (temperatureSensors > 1) {
    telemetry.temperature2 = static_cast<float>(readU16(d + 69 - 3)) - 40.0f;
  }

  telemetry.packVoltage = static_cast<float>(readU16(d + 83 - 3)) * 0.1f;
  telemetry.packCurrent = (static_cast<float>(readU16(d + 85 - 3)) - 30000.0f) * 0.1f;
  telemetry.power = telemetry.packVoltage * telemetry.packCurrent;
  telemetry.stateOfCharge = static_cast<float>(readU16(d + 87 - 3)) * 0.1f;
  telemetry.remainingCapacityAh = static_cast<float>(readU16(d + 99 - 3)) * 0.1f;
  telemetry.cycleCount = readU16(d + 105 - 3);
  telemetry.balancingActive = readU16(d + 107 - 3) == 0x0001;
  telemetry.chargingEnabled = readU16(d + 109 - 3) == 0x0001;
  telemetry.dischargingEnabled = readU16(d + 111 - 3) == 0x0001;
  telemetry.errorsBitmask = static_cast<uint32_t>(readU64(d + 119 - 3));

  if (length == kStatusFrameLen80) {
    telemetry.balancingCurrent = (static_cast<float>(readU16(d + 131 - 3)) - 30000.0f) * 0.001f;
    telemetry.mosfetTemperature = static_cast<float>(readU16(d + 135 - 3)) - 40.0f;
    // No dedicated BatteryTelemetry field for a separate board temperature
    // (distinct from the pack's own T1/T2 sensors) — not decoded.
  }

  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr
