#include "JbdBmsParser.h"

#include <string.h>

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0xDD;
constexpr uint8_t kFrameEnd = 0x77;
constexpr uint8_t kCmdHardwareInfo = 0x03;
constexpr uint8_t kCmdCellInfo = 0x04;
constexpr size_t kMaxTemperatureSensors = 6;

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint32_t readU32(const uint8_t* p) {
  return (static_cast<uint32_t>(readU16(p)) << 16) | readU16(p + 2);
}

// JBD's checksum is the two's-complement negation of the byte sum (wrapping
// in 16 bits), computed over the status/length/data span of a response.
uint16_t frameChecksum(const uint8_t* data, size_t length) {
  uint16_t checksum = 0;
  for (size_t index = 0; index < length; ++index) {
    checksum = static_cast<uint16_t>(checksum - data[index]);
  }
  return checksum;
}

}  // namespace

bool JbdBmsParser::parseFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < 7) {
    return false;
  }
  if (frame[0] != kFrameStart || frame[length - 1] != kFrameEnd) {
    return false;
  }
  const uint8_t function = frame[1];
  const uint8_t responseStatus = frame[2];
  const size_t dataLen = frame[3];
  if (length != 4 + dataLen + 3) {
    return false;
  }
  if (responseStatus != 0) {
    return false;  // BMS reported an error for this command
  }
  const uint16_t computedChecksum = frameChecksum(frame + 2, dataLen + 2);
  const uint16_t remoteChecksum = readU16(frame + 4 + dataLen);
  if (computedChecksum != remoteChecksum) {
    return false;
  }

  const uint8_t* d = frame + 4;

  if (function == kCmdHardwareInfo) {
    if (dataLen < 22) {
      return false;
    }
    // Byte offsets per syssi/esphome-jbd-bms's documented HWINFO frame.
    telemetry.packVoltage = static_cast<float>(readU16(d)) * 0.01f;
    telemetry.packCurrent = static_cast<float>(static_cast<int16_t>(readU16(d + 2))) * 0.01f;
    telemetry.power = telemetry.packVoltage * telemetry.packCurrent;
    telemetry.remainingCapacityAh = static_cast<float>(readU16(d + 4)) * 0.01f;
    telemetry.fullCapacityAh = static_cast<float>(readU16(d + 6)) * 0.01f;
    telemetry.cycleCount = readU16(d + 8);
    const uint32_t balanceBitmask = readU32(d + 12);
    telemetry.balancingActive = balanceBitmask > 0;
    telemetry.errorsBitmask = readU16(d + 16);
    telemetry.stateOfCharge = static_cast<float>(d[19]);
    const uint8_t operationStatus = d[20];
    telemetry.chargingEnabled = (operationStatus & 0x01) != 0;
    telemetry.dischargingEnabled = (operationStatus & 0x02) != 0;
    telemetry.cellCount = d[21];
    if (dataLen >= 23) {
      const uint8_t temperatureSensors =
          d[22] < kMaxTemperatureSensors ? d[22] : static_cast<uint8_t>(kMaxTemperatureSensors);
      telemetry.temperatureSensorCount = temperatureSensors;
      if (dataLen >= 23u + static_cast<size_t>(temperatureSensors) * 2 && temperatureSensors > 0) {
        telemetry.temperature1 = (static_cast<float>(readU16(d + 23)) - 2731.0f) * 0.1f;
        if (temperatureSensors > 1) {
          telemetry.temperature2 = (static_cast<float>(readU16(d + 25)) - 2731.0f) * 0.1f;
        }
      }
    }
    return true;
  }

  if (function == kCmdCellInfo) {
    const uint8_t cells = static_cast<uint8_t>(dataLen / 2 > kMaxCellCount ? kMaxCellCount : dataLen / 2);
    if (cells == 0) {
      return false;
    }
    telemetry.minCellVoltage = 100.0f;
    telemetry.maxCellVoltage = -100.0f;
    float sum = 0.0f;
    for (uint8_t cell = 0; cell < cells; ++cell) {
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
    telemetry.avgCellVoltage = sum / cells;
    telemetry.deltaCellVoltage = telemetry.maxCellVoltage - telemetry.minCellVoltage;
    return true;
  }

  return false;
}

}  // namespace jkbmsr
