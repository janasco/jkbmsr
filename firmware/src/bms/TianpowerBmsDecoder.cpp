#include "TianpowerBmsDecoder.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0x55;
constexpr uint8_t kResponseMarker = 0x14;
constexpr uint8_t kFrameEnd = 0xAA;

uint16_t readU16Be(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

int16_t readS16Be(const uint8_t* p) {
  return static_cast<int16_t>(readU16Be(p));
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

void TianpowerBmsDecoder::buildRequestFrame(uint8_t frame[kRequestFrameSize], uint8_t frameType) {
  frame[0] = kFrameStart;
  frame[1] = 0x04;  // request marker
  frame[2] = frameType;
  frame[3] = kFrameEnd;
}

bool TianpowerBmsDecoder::isCompleteFrame(const uint8_t* frame, size_t length) {
  return frame != nullptr && length == kResponseFrameSize && frame[0] == kFrameStart && frame[19] == kFrameEnd;
}

bool TianpowerBmsDecoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (!isCompleteFrame(frame, length) || frame[1] != kResponseMarker || frame[2] != kFrameTypeStatus) {
    return false;
  }

  telemetry.source = "ble";
  const float totalVoltage = static_cast<float>(readU16Be(frame + 5)) * 0.01f;
  const float current = static_cast<float>(readS16Be(frame + 13)) * 0.01f;
  telemetry.packVoltage = totalVoltage;
  telemetry.packCurrent = current;
  telemetry.power = totalVoltage * current;
  telemetry.stateOfCharge = static_cast<float>(readU16Be(frame + 3));
  if (telemetry.stateOfCharge < 0.0f) {
    telemetry.stateOfCharge = 0.0f;
  } else if (telemetry.stateOfCharge > 100.0f) {
    telemetry.stateOfCharge = 100.0f;
  }
  telemetry.temperatureSensorCount = 2;
  telemetry.temperature1 = static_cast<float>(readS16Be(frame + 7)) * 0.1f;
  telemetry.temperature2 = static_cast<float>(readS16Be(frame + 9)) * 0.1f;
  telemetry.mosfetTemperature = static_cast<float>(readS16Be(frame + 11)) * 0.1f;

  telemetry.valid = true;
  return true;
}

bool TianpowerBmsDecoder::parseCellChunkFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (!isCompleteFrame(frame, length) || frame[1] != kResponseMarker) {
    return false;
  }
  const uint8_t type = frame[2];
  if (type != kFrameTypeCellVoltages1_8 && type != kFrameTypeCellVoltages9_16) {
    return false;
  }
  const uint8_t chunk = type - kFrameTypeCellVoltages1_8;
  const size_t base = static_cast<size_t>(chunk) * 8;
  uint8_t cells = static_cast<uint8_t>(base + 8);
  if (cells > kMaxCellCount) {
    cells = kMaxCellCount;
  }
  telemetry.cellCount = cells;
  for (uint8_t i = 0; i < 8; ++i) {
    telemetry.cellVoltages[static_cast<size_t>(base) + i] =
        static_cast<float>(readU16Be(frame + 3 + static_cast<size_t>(i) * 2)) * 0.001f;
  }
  recomputeCellStats(telemetry);
  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr