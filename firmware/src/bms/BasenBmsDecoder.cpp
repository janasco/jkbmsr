#include "BasenBmsDecoder.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStartA = 0x3A;
constexpr uint8_t kFrameStartB = 0x3B;
constexpr uint8_t kFrameAddr = 0x16;
constexpr uint8_t kFrameEnd1 = 0x0D;
constexpr uint8_t kFrameEnd2 = 0x0A;

uint8_t readU8(const uint8_t* p) {
  return p[0];
}

uint16_t readU16Le(const uint8_t* p) {
  return static_cast<uint16_t>(static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8));
}

uint32_t readU32Le(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

int32_t readS32Le(const uint8_t* p) {
  return static_cast<int32_t>(readU32Le(p));
}

bool isValidFrameStart(uint8_t sof) {
  return sof == kFrameStartA || sof == kFrameStartB;
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

void BasenBmsDecoder::buildRequestFrame(uint8_t frame[kMaxRequestFrameSize], uint8_t frameType) {
  frame[0] = kFrameStartA;
  frame[1] = kFrameAddr;
  frame[2] = frameType;
  frame[3] = 0x00;  // payload length
  uint16_t sum = 0;
  for (uint8_t i = 1; i < 4; ++i) {
    sum += frame[i];
  }
  frame[4] = static_cast<uint8_t>(sum);
  frame[5] = static_cast<uint8_t>(sum >> 8);
  frame[6] = kFrameEnd1;
  frame[7] = kFrameEnd2;
}

size_t BasenBmsDecoder::frameCompleteLength(const uint8_t* frame, size_t length) {
  if (frame == nullptr || length < 8 || !isValidFrameStart(frame[0])) {
    return 0;
  }
  const size_t frameLen = 4 + static_cast<size_t>(frame[3]) + 4;
  if (frameLen > length) {
    return 0;
  }
  if (frame[frameLen - 2] != kFrameEnd1 || frame[frameLen - 1] != kFrameEnd2) {
    return 0;
  }
  return frameLen;
}

bool BasenBmsDecoder::validateChecksum(const uint8_t* frame, size_t frameLen) {
  const size_t dataLen = frame[3];
  if (frameLen != 4 + dataLen + 4) {
    return false;
  }
  uint32_t sum = 0;
  for (size_t i = 1; i <= 3 + dataLen; ++i) {
    sum += frame[i];
  }
  const uint16_t remote = static_cast<uint16_t>(frame[frameLen - 4]) |
                          (static_cast<uint16_t>(frame[frameLen - 3]) << 8);
  return (sum & 0xFFFF) == remote;
}

bool BasenBmsDecoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  const size_t frameLen = frameCompleteLength(frame, length);
  if (frameLen == 0 || frameLen != length || frame[1] != kFrameAddr || frame[2] != kFrameTypeStatus ||
      !validateChecksum(frame, length)) {
    return false;
  }

  telemetry.source = "ble";
  telemetry.valid = true;

  const int32_t currentRaw = readS32Le(frame + 4);
  const float current = static_cast<float>(currentRaw) * 0.001f;
  const float totalVoltage = static_cast<float>(readU32Le(frame + 8)) * 0.001f;
  telemetry.packCurrent = current;
  telemetry.packVoltage = totalVoltage;
  telemetry.power = totalVoltage * current;

  telemetry.temperatureSensorCount = 4;
  telemetry.temperature1 = static_cast<float>(static_cast<int8_t>(readU8(frame + 12)));
  telemetry.temperature2 = static_cast<float>(static_cast<int8_t>(readU8(frame + 13)));
  telemetry.mosfetTemperature = static_cast<float>(static_cast<int8_t>(readU8(frame + 15)));

  telemetry.remainingCapacityAh = static_cast<float>(readU32Le(frame + 16)) * 0.001f;
  telemetry.chargingEnabled = (frame[20] & (1 << 7)) != 0;
  telemetry.dischargingEnabled = (frame[21] & (1 << 7)) != 0;
  telemetry.errorsBitmask = static_cast<uint32_t>(frame[22]) | (static_cast<uint32_t>(frame[23]) << 8);
  telemetry.stateOfCharge = static_cast<float>(frame[24]);
  if (telemetry.stateOfCharge > 100.0f) {
    telemetry.stateOfCharge = 100.0f;
  }

  return true;
}

bool BasenBmsDecoder::parseGeneralInfoFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  const size_t frameLen = frameCompleteLength(frame, length);
  if (frameLen == 0 || frameLen != length || frame[1] != kFrameAddr || frame[2] != kFrameTypeGeneralInfo ||
      !validateChecksum(frame, length)) {
    return false;
  }

  telemetry.source = "ble";
  const float nominalCapacity = static_cast<float>(readU32Le(frame + 4)) * 0.001f;
  const float realCapacity = static_cast<float>(readU32Le(frame + 12)) * 0.001f;
  telemetry.fullCapacityAh = nominalCapacity > 0.0f ? nominalCapacity : realCapacity;
  telemetry.cycleCount = readU16Le(frame + 26);
  return true;
}

bool BasenBmsDecoder::parseCellChunkFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  const size_t frameLen = frameCompleteLength(frame, length);
  if (frameLen == 0 || frameLen != length || frame[1] != kFrameAddr || !validateChecksum(frame, length)) {
    return false;
  }
  const uint8_t type = frame[2];
  if (type != kFrameTypeCellVoltages1_12 && type != kFrameTypeCellVoltages13_24) {
    return false;
  }
  const uint8_t chunk = type - kFrameTypeCellVoltages1_12;
  const size_t base = static_cast<size_t>(chunk) * kCellsPerChunk;
  // frame[3] is the declared payload length and is fully attacker/radio
  // controlled (0..255). frameCompleteLength only proves the declared frame
  // fits the assembly buffer, not that it holds one chunk's worth of cells.
  // Without this bound a frame declaring length 120 yields cellsInFrame=60,
  // writing telemetry.cellVoltages[12..71] past kMaxCellCount(32) and
  // corrupting the fields that follow it in BatteryTelemetry.
  const uint8_t cellsInFrame = frame[3] / 2;
  if (cellsInFrame > kCellsPerChunk || base + cellsInFrame > kMaxCellCount) {
    return false;
  }
  uint8_t count = 0;
  for (uint8_t i = 0; i < cellsInFrame; ++i) {
    const float voltage = static_cast<float>(readU16Le(frame + 4 + static_cast<size_t>(i) * 2)) * 0.001f;
    telemetry.cellVoltages[base + i] = voltage;
    if (voltage > 0.0f) {
      count = static_cast<uint8_t>(i + 1);
    }
  }
  const uint8_t mergedCount = static_cast<uint8_t>(base + count);
  if (mergedCount > telemetry.cellCount) {
    telemetry.cellCount = mergedCount;
  }
  if (telemetry.cellCount > kMaxCellCount) {
    telemetry.cellCount = kMaxCellCount;
  }
  recomputeCellStats(telemetry);
  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr