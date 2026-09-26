#include "LolanBmsDecoder.h"

#include <string.h>

namespace jkbmsr {

namespace {

constexpr uint8_t kMaxLolanCells = 16;

uint16_t readU16Be(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint32_t readU32Be(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) << 24 | static_cast<uint32_t>(p[1]) << 16 |
         static_cast<uint32_t>(p[2]) << 8 | static_cast<uint32_t>(p[3]);
}

void recomputeCellStats(BatteryTelemetry& telemetry) {
  telemetry.minCellVoltage = 100.0f;
  telemetry.maxCellVoltage = -100.0f;
  float voltageSum = 0.0f;
  uint8_t counted = 0;
  for (uint8_t cell = 0; cell < telemetry.cellCount; ++cell) {
    const float voltage = telemetry.cellVoltages[cell];
    if (voltage <= 0.0f) {
      continue;
    }
    voltageSum += voltage;
    ++counted;
    if (voltage < telemetry.minCellVoltage) {
      telemetry.minCellVoltage = voltage;
      telemetry.minVoltageCell = static_cast<uint8_t>(cell + 1);
    }
    if (voltage > telemetry.maxCellVoltage) {
      telemetry.maxCellVoltage = voltage;
      telemetry.maxVoltageCell = static_cast<uint8_t>(cell + 1);
    }
  }
  if (counted > 0) {
    telemetry.avgCellVoltage = voltageSum / counted;
    telemetry.deltaCellVoltage = telemetry.maxCellVoltage - telemetry.minCellVoltage;
  } else {
    telemetry.minCellVoltage = 0.0f;
    telemetry.maxCellVoltage = 0.0f;
    telemetry.avgCellVoltage = 0.0f;
    telemetry.deltaCellVoltage = 0.0f;
  }
}

}  // namespace

void LolanBmsDecoder::buildCommandFrame(uint8_t frame[kRequestFrameSize], uint16_t command, uint32_t password) {
  frame[0] = static_cast<uint8_t>(command >> 8);
  frame[1] = static_cast<uint8_t>(command);
  frame[2] = static_cast<uint8_t>(password >> 24);
  frame[3] = static_cast<uint8_t>(password >> 16);
  frame[4] = static_cast<uint8_t>(password >> 8);
  frame[5] = static_cast<uint8_t>(password);
}

size_t LolanBmsDecoder::responseSizeFor(const uint8_t* frame, size_t length) {
  if (frame == nullptr || length == 0) {
    return 0;
  }
  switch (frame[0]) {
    case kFrameTypeStatus:
    case kFrameTypeCellInfo:
      return kStatusFrameSize;
    case kFrameTypeSettings:
      return 108;
    default:
      return 0;
  }
}

float LolanBmsDecoder::beFloat32(const uint8_t* p) {
  const uint32_t bits = readU32Be(p);
  float value;
  static_assert(sizeof(value) == sizeof(bits), "float must be 32-bit");
  memcpy(&value, &bits, sizeof(bits));
  return value;
}

bool LolanBmsDecoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < kStatusFrameSize || frame[0] != kFrameTypeStatus) {
    return false;
  }

  telemetry.source = "ble";
  telemetry.valid = true;

  telemetry.dischargingEnabled = (frame[2] & (1 << 1)) != 0;
  telemetry.chargingEnabled = (frame[2] & (1 << 2)) != 0;
  telemetry.errorsBitmask = frame[3];

  const float totalVoltage = beFloat32(frame + 4);
  const float negativeCurrent = beFloat32(frame + 8);
  const float positiveCurrent = beFloat32(frame + 12);
  const float current = negativeCurrent > positiveCurrent ? -negativeCurrent : positiveCurrent;
  telemetry.packVoltage = totalVoltage;
  telemetry.packCurrent = current;
  telemetry.power = totalVoltage * current;

  telemetry.temperature1 = beFloat32(frame + 16);
  telemetry.temperature2 = beFloat32(frame + 20);

  telemetry.cycleCount = readU16Be(frame + 36);
  telemetry.stateOfCharge = static_cast<float>(readU16Be(frame + 38));
  if (telemetry.stateOfCharge < 0.0f) {
    telemetry.stateOfCharge = 0.0f;
  } else if (telemetry.stateOfCharge > 100.0f) {
    telemetry.stateOfCharge = 100.0f;
  }

  return true;
}

bool LolanBmsDecoder::parseCellInfoFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < kStatusFrameSize || frame[0] != kFrameTypeCellInfo) {
    return false;
  }

  uint8_t cellCount = frame[2];
  if (cellCount > kMaxLolanCells) {
    cellCount = kMaxLolanCells;
  }
  telemetry.balancingActive = false;
  const uint32_t balancingMask = readU32Be(frame + 8);
  uint8_t counted = 0;
  for (uint8_t cell = 0; cell < cellCount; ++cell) {
    const size_t offset = 24 + static_cast<size_t>(cell) * 4;
    if (offset + 4 > length) {
      break;
    }
    const float voltage = beFloat32(frame + offset);
    telemetry.cellVoltages[cell] = voltage;
    if (voltage > 0.0f) {
      counted = static_cast<uint8_t>(cell + 1);
    }
    if ((balancingMask & (static_cast<uint32_t>(1) << cell)) != 0) {
      telemetry.balancingActive = true;
    }
  }
  telemetry.cellCount = counted;
  recomputeCellStats(telemetry);
  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr