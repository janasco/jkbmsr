#include "AntBmsDecoder.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart1 = 0x7E;
constexpr uint8_t kFrameStart2 = 0xA1;
constexpr uint8_t kRequestFunction = 0x01;
constexpr uint8_t kStatusFunction = 0x11;
constexpr uint8_t kMaxAntCells = 32;
constexpr uint8_t kMaxAntTemps = 4;

uint16_t readU16Le(const uint8_t* p) {
  return static_cast<uint16_t>(static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8));
}

int32_t readS32Le(const uint8_t* p) {
  return static_cast<int32_t>(static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
                              (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24));
}

uint32_t readU32Le(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

}  // namespace

uint16_t AntBmsDecoder::crc16Modbus(const uint8_t* data, size_t length) {
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

void AntBmsDecoder::buildStatusRequest(uint8_t frame[kRequestFrameSize]) {
  frame[0] = kFrameStart1;
  frame[1] = kFrameStart2;
  frame[2] = kRequestFunction;
  frame[3] = 0x00;  // address low
  frame[4] = 0x00;  // address high
  frame[5] = 0xBE;  // status-request value marker (not a length; see syssi
                    // build_frame: crc runs over frame[1..5] only).
  const uint16_t crc = crc16Modbus(frame + 1, 5);
  frame[6] = static_cast<uint8_t>(crc);
  frame[7] = static_cast<uint8_t>(crc >> 8);
  frame[8] = 0xAA;
  frame[9] = 0x55;
}

bool AntBmsDecoder::parseStatusFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < 10) {
    return false;
  }
  if (frame[0] != kFrameStart1 || frame[1] != kFrameStart2) {
    return false;
  }
  const uint16_t dataLen = frame[5];
  const size_t frameLen = 6 + static_cast<size_t>(dataLen) + 4;
  if (length != frameLen) {
    return false;
  }
  if (frame[frameLen - 2] != 0xAA || frame[frameLen - 1] != 0x55) {
    return false;
  }
  const uint16_t computedCrc = crc16Modbus(frame + 1, frameLen - 5);
  const uint16_t remoteCrc = static_cast<uint16_t>(frame[frameLen - 4]) |
                             (static_cast<uint16_t>(frame[frameLen - 3]) << 8);
  if (computedCrc != remoteCrc) {
    return false;
  }
  if (frame[2] != kStatusFunction) {
    return false;
  }

  const uint8_t temperatureSensors = frame[8];
  const uint8_t rawCellCount = frame[9];
  if (rawCellCount > kMaxAntCells || temperatureSensors > kMaxAntTemps) {
    return false;
  }
  const size_t offset = static_cast<size_t>(rawCellCount) * 2 + static_cast<size_t>(temperatureSensors) * 2;
  // tailOffset (below) = 34 + offset + 4; the last field we read is power
  // (s32 at tailOffset+24), so the frame must reach 34+offset+4+28.
  const size_t minLen = 34 + offset + 4 + 28;
  if (length < minLen) {
    return false;
  }

  telemetry.source = "ble";

  const uint8_t cellCount = rawCellCount > 0 ? rawCellCount : 1;
  telemetry.cellCount = cellCount;
  telemetry.minCellVoltage = 100.0f;
  telemetry.maxCellVoltage = -100.0f;
  float voltageSum = 0.0f;
  for (uint8_t cell = 0; cell < cellCount; ++cell) {
    const float voltage = static_cast<float>(readU16Le(frame + 34 + static_cast<size_t>(cell) * 2)) * 0.001f;
    telemetry.cellVoltages[cell] = voltage;
    voltageSum += voltage;
    if (voltage < telemetry.minCellVoltage) {
      telemetry.minCellVoltage = voltage;
      telemetry.minVoltageCell = static_cast<uint8_t>(cell + 1);
    }
    if (voltage > telemetry.maxCellVoltage) {
      telemetry.maxCellVoltage = voltage;
      telemetry.maxVoltageCell = static_cast<uint8_t>(cell + 1);
    }
  }
  telemetry.avgCellVoltage = voltageSum / cellCount;
  telemetry.deltaCellVoltage = telemetry.maxCellVoltage - telemetry.minCellVoltage;

  telemetry.temperatureSensorCount = temperatureSensors;
  const size_t tempBlockOffset = 34 + static_cast<size_t>(rawCellCount) * 2;
  if (temperatureSensors > 0) {
    telemetry.temperature1 = static_cast<float>(static_cast<int16_t>(readU16Le(frame + tempBlockOffset)));
  }
  if (temperatureSensors > 1) {
    telemetry.temperature2 = static_cast<float>(static_cast<int16_t>(readU16Le(frame + tempBlockOffset + 2)));
  }
  // MOSFET temp and balancer temp follow the NTC block.
  const size_t mosTempOffset = tempBlockOffset + static_cast<size_t>(temperatureSensors) * 2;
  telemetry.mosfetTemperature =
      static_cast<float>(static_cast<int16_t>(readU16Le(frame + mosTempOffset)));

  const size_t tailOffset = mosTempOffset + 4;  // +4: balancer temp (2) + gap
  telemetry.packVoltage = static_cast<float>(readU16Le(frame + tailOffset)) * 0.01f;
  const float current = static_cast<float>(static_cast<int16_t>(readU16Le(frame + tailOffset + 2))) * 0.1f;
  telemetry.packCurrent = current;
  telemetry.stateOfCharge = static_cast<float>(static_cast<int16_t>(readU16Le(frame + tailOffset + 4)));
  if (telemetry.stateOfCharge < 0.0f) {
    telemetry.stateOfCharge = 0.0f;
  } else if (telemetry.stateOfCharge > 100.0f) {
    telemetry.stateOfCharge = 100.0f;
  }
  const uint16_t stateOfHealthRaw = readU16Le(frame + tailOffset + 6);
  telemetry.stateOfHealth = stateOfHealthRaw > 100 ? 100 : static_cast<uint8_t>(stateOfHealthRaw);

  telemetry.chargingEnabled = frame[tailOffset + 8] == 0x01;
  telemetry.dischargingEnabled = frame[tailOffset + 9] == 0x01;

  // raw_battery_status (tailOffset+10) reports balancing-activity state with
  // value 0x04 (syssi's BALANCER_STATUS[4] = "Automatic equalization"); the
  // per-cell balancing bitmask at frame 26..33 is authoritative for whether a
  // balancing pass is running, handled below.
  telemetry.fullCapacityAh = static_cast<float>(readU32Le(frame + tailOffset + 12)) * 0.000001f;
  telemetry.remainingCapacityAh = static_cast<float>(readU32Le(frame + tailOffset + 16)) * 0.000001f;
  telemetry.cycleCapacityAh = static_cast<float>(readU32Le(frame + tailOffset + 20)) * 0.001f;
  telemetry.power = static_cast<float>(readS32Le(frame + tailOffset + 24));

  // Protections (frame 10..17) plus warnings (frame 18..25), packed into the
  // shared bitmask: low 16 bits = protections, high 16 bits = warnings. This
  // mirrors how every other brand collapses multiple status words into one
  // errorsBitmask; see the syssi PROTECTIONS_STATUS/WARNINGS comment blocks.
  const uint32_t protections = readU32Le(frame + 10);
  const uint32_t warnings = readU32Le(frame + 18);
  telemetry.errorsBitmask = protections | (warnings << 16);
  telemetry.balancingActive = readU32Le(frame + 26) != 0;

  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr