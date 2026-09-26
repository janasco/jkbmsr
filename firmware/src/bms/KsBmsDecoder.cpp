#include "KsBmsDecoder.h"

namespace jkbmsr {

namespace {

uint16_t readU16Be(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

int16_t readS16Be(const uint8_t* p) {
  return static_cast<int16_t>(readU16Be(p));
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

void KsBmsDecoder::buildCommandFrame(uint8_t frame[kRequestFrameSize], uint8_t frameType) {
  frame[0] = kFrameStart;
  frame[1] = frameType;
  frame[2] = 0x00;
  frame[3] = kFrameEnd;
}

bool KsBmsDecoder::isCompleteFrame(const uint8_t* frame, size_t length) {
  if (frame == nullptr || length < 4) {
    return false;
  }
  if (frame[0] != kFrameStart || frame[length - 1] != kFrameEnd) {
    return false;
  }
  return length == static_cast<size_t>(frame[2]) + 4;
}

bool KsBmsDecoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (!isCompleteFrame(frame, length)) {
    return false;
  }
  const uint8_t type = frame[1];
  if (type != kFrameTypeStatus && type != kFrameTypeStatusType2) {
    return false;
  }
  if (length < 33) {
    return false;
  }

  telemetry.source = "ble";
  telemetry.valid = true;

  telemetry.stateOfCharge = static_cast<float>(readU16Be(frame + 3));
  if (telemetry.stateOfCharge < 0.0f) {
    telemetry.stateOfCharge = 0.0f;
  } else if (telemetry.stateOfCharge > 100.0f) {
    telemetry.stateOfCharge = 100.0f;
  }
  const float totalVoltage = static_cast<float>(readU16Be(frame + 5)) * 0.01f;
  const float current = static_cast<float>(readS16Be(frame + 13)) * 0.01f;
  telemetry.packVoltage = totalVoltage;
  telemetry.packCurrent = current;
  telemetry.power = totalVoltage * current;

  telemetry.temperatureSensorCount = 2;
  telemetry.temperature1 = static_cast<float>(readS16Be(frame + 7)) * 0.1f;
  telemetry.temperature2 = static_cast<float>(readS16Be(frame + 9)) * 0.1f;
  telemetry.mosfetTemperature = static_cast<float>(readS16Be(frame + 11)) * 0.1f;

  telemetry.remainingCapacityAh = static_cast<float>(readU16Be(frame + 15)) * 0.01f;
  telemetry.fullCapacityAh = static_cast<float>(readU16Be(frame + 17)) * 0.01f;
  telemetry.cycleCapacityAh = static_cast<float>(readU16Be(frame + 21)) * 0.01f;
  telemetry.cycleCount = readU16Be(frame + 23);

  telemetry.balancingActive = readU32Be(frame + 25) != 0;

  const uint16_t fetStatus = readU16Be(frame + 29);
  telemetry.chargingEnabled = (fetStatus & 0x04) != 0;
  telemetry.dischargingEnabled = (fetStatus & 0x08) != 0;
  if (!telemetry.balancingActive) {
    telemetry.balancingActive = (fetStatus & 0x03) != 0;
  }

  telemetry.errorsBitmask = readU16Be(frame + 31);

  if (length > 34) {
    const uint16_t stateOfHealthRaw = readU16Be(frame + 33);
    telemetry.stateOfHealth = stateOfHealthRaw > 100 ? 100 : static_cast<uint8_t>(stateOfHealthRaw);
  }

  return true;
}

bool KsBmsDecoder::parseCellVoltagesFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (!isCompleteFrame(frame, length)) {
    return false;
  }
  if (frame[1] != kFrameTypeCellVoltages || length < 6) {
    return false;
  }
  uint8_t cellCount = frame[3];
  if (cellCount > kMaxKsCells) {
    cellCount = kMaxKsCells;
  }
  if (static_cast<size_t>(cellCount) * 2 + 4 > length) {
    return false;
  }
  for (uint8_t cell = 0; cell < cellCount; ++cell) {
    const float voltage = static_cast<float>(readU16Be(frame + 4 + static_cast<size_t>(cell) * 2)) * 0.001f;
    telemetry.cellVoltages[cell] = voltage;
  }
  telemetry.cellCount = cellCount;
  recomputeCellStats(telemetry);
  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr