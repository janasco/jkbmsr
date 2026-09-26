#include "SeplosBleDecoder.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0x7E;
constexpr uint8_t kFrameEnd = 0x0D;
constexpr uint8_t kVersion = 0x10;
constexpr uint8_t kAddress = 0x00;
constexpr uint8_t kCid1 = 0x46;
constexpr uint8_t kCmdGetSingleMachineData = 0x61;
constexpr uint8_t kMaxSeplosCells = 24;  // matches upstream's own cells_[24] bound
constexpr float kKelvinOffsetDeciKelvin = 2731.0f;

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

}  // namespace

uint16_t SeplosBleDecoder::crc16Xmodem(const uint8_t* data, size_t length) {
  uint16_t crc = 0x0000;
  for (size_t i = 0; i < length; ++i) {
    crc ^= static_cast<uint16_t>(data[i]) << 8;
    for (int bit = 0; bit < 8; ++bit) {
      if (crc & 0x8000) {
        crc = static_cast<uint16_t>((crc << 1) ^ 0x1021);
      } else {
        crc = static_cast<uint16_t>(crc << 1);
      }
    }
  }
  return crc;
}

void SeplosBleDecoder::buildSingleMachineDataRequest(uint8_t frame[kRequestFrameSize]) {
  frame[0] = kFrameStart;
  frame[1] = kVersion;
  frame[2] = kAddress;
  frame[3] = kCid1;
  frame[4] = kCmdGetSingleMachineData;
  frame[5] = 0x00;  // payload length, high byte
  frame[6] = 0x01;  // payload length, low byte (1 byte)
  frame[7] = 0x00;  // payload: device address
  const uint16_t crc = crc16Xmodem(frame + 1, 7);
  frame[8] = static_cast<uint8_t>(crc >> 8);
  frame[9] = static_cast<uint8_t>(crc);
  frame[10] = kFrameEnd;
}

bool SeplosBleDecoder::parseSingleMachineDataFrame(const uint8_t* frame, size_t length,
                                                   BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < 7) {
    return false;
  }
  if (frame[0] != kFrameStart) {
    return false;
  }

  const uint16_t declaredPayloadLen = readU16(frame + 5);
  const size_t frameLen = 7 + static_cast<size_t>(declaredPayloadLen) + 2 + 1;
  if (length != frameLen) {
    return false;
  }
  if (frame[frameLen - 1] != kFrameEnd) {
    return false;
  }

  const uint16_t computedCrc = crc16Xmodem(frame + 1, frameLen - 4);
  const uint16_t remoteCrc =
      static_cast<uint16_t>((static_cast<uint16_t>(frame[frameLen - 3]) << 8) | frame[frameLen - 2]);
  if (computedCrc != remoteCrc) {
    return false;
  }

  // The command byte is at frame[4]; frame[3] is the fixed CID (kCid1 =
  // 0x46) on both request and response frames — see buildRequestFrame, which
  // writes kCid1 to [3] and kCmdGetSingleMachineData to [4], and the
  // documented `7E 10 00 46 <func> <lenHi lenLo> ...` layout. Checking
  // frame[3] here compared 0x46 against 0x61 and so rejected every real
  // device. The committed test never caught this because no firmware test
  // has ever actually executed.
  if (frame[4] != kCmdGetSingleMachineData) {
    return false;
  }

  const uint8_t* data = frame;
  if (length < 60) {
    return false;
  }

  const uint8_t cells = data[9];
  // Bound `cells` BEFORE using it as an offset. data[9] is a radio-controlled
  // byte and the length < 60 check above says nothing about it: cells=200
  // makes the temperature lookup below read offset 410, far past the client's
  // 256-byte assembly buffer. The frame is rejected later either way, but the
  // read itself is undefined behaviour.
  if (cells > kMaxSeplosCells) {
    return false;
  }
  const uint8_t temperatures = data[7 + 3 + static_cast<size_t>(cells) * 2];
  const size_t minLen = 7 + 3 + (static_cast<size_t>(cells) * 2) + 1 + (static_cast<size_t>(temperatures) * 2) +
                         58 + 2 + 1;
  if (length < minLen) {
    return false;
  }

  telemetry.source = "ble";

  const uint8_t actualCellCount = cells;
  telemetry.cellCount = actualCellCount;
  telemetry.minCellVoltage = 100.0f;
  telemetry.maxCellVoltage = -100.0f;
  float voltageSum = 0.0f;
  for (uint8_t cell = 0; cell < actualCellCount; ++cell) {
    const float voltage = static_cast<float>(readU16(data + 10 + static_cast<size_t>(cell) * 2)) * 0.001f;
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
  if (actualCellCount > 0) {
    telemetry.avgCellVoltage = voltageSum / actualCellCount;
    telemetry.deltaCellVoltage = telemetry.maxCellVoltage - telemetry.minCellVoltage;
  }

  // `temperatures` counts every sensor including 2 non-cell ones (ambient +
  // MOSFET) appended after the cell-temperature readings.
  const uint8_t cellTemperatures = temperatures > 2 ? static_cast<uint8_t>(temperatures - 2) : 0;
  telemetry.temperatureSensorCount = cellTemperatures;
  const size_t tempBlockOffset = 7 + 3 + (static_cast<size_t>(cells) * 2) + 1;
  if (cellTemperatures > 0) {
    telemetry.temperature1 = (static_cast<float>(readU16(data + tempBlockOffset)) - kKelvinOffsetDeciKelvin) * 0.1f;
  }
  if (cellTemperatures > 1) {
    telemetry.temperature2 =
        (static_cast<float>(readU16(data + tempBlockOffset + 2)) - kKelvinOffsetDeciKelvin) * 0.1f;
  }
  const float ambientTemperature =
      (static_cast<float>(readU16(data + tempBlockOffset + static_cast<size_t>(cellTemperatures) * 2)) -
       kKelvinOffsetDeciKelvin) *
      0.1f;
  if (cellTemperatures == 0) {
    telemetry.temperature1 = ambientTemperature;
  }
  telemetry.mosfetTemperature =
      (static_cast<float>(readU16(data + tempBlockOffset + static_cast<size_t>(cellTemperatures) * 2 + 2)) -
       kKelvinOffsetDeciKelvin) *
      0.1f;

  const size_t block2Offset =
      7 + 3 + (static_cast<size_t>(cells) * 2) + 1 + (static_cast<size_t>(temperatures) * 2);
  const int16_t currentRaw = static_cast<int16_t>(readU16(data + block2Offset));
  const float current = static_cast<float>(currentRaw) * 0.01f;
  telemetry.packCurrent = current;
  const float totalVoltage = static_cast<float>(readU16(data + block2Offset + 2)) * 0.01f;
  telemetry.packVoltage = totalVoltage;
  telemetry.power = totalVoltage * current;
  telemetry.remainingCapacityAh = static_cast<float>(readU16(data + block2Offset + 4)) * 0.01f;
  // +6: reserved. +7: "battery capacity" register — not mapped, semantics
  // not confirmed against real hardware (distinct from both the remaining
  // and nominal capacity registers below).
  telemetry.stateOfCharge = static_cast<float>(readU16(data + block2Offset + 9)) * 0.1f;
  telemetry.fullCapacityAh = static_cast<float>(readU16(data + block2Offset + 11)) * 0.01f;
  telemetry.cycleCount = readU16(data + block2Offset + 13);
  const uint16_t stateOfHealthRaw = readU16(data + block2Offset + 15);  // x0.1 percent
  uint16_t stateOfHealthPercent = static_cast<uint16_t>((stateOfHealthRaw + 5) / 10);
  if (stateOfHealthPercent > 100) {
    stateOfHealthPercent = 100;
  }
  telemetry.stateOfHealth = static_cast<uint8_t>(stateOfHealthPercent);
  // +17: port voltage — not mapped, no corresponding BatteryTelemetry field.

  const size_t block3Offset = block2Offset + 19;
  const size_t protectionOffset = block3Offset + cells + temperatures;
  const size_t alarmOffset = protectionOffset + 5;
  if (alarmOffset + 3 >= length) {
    return false;
  }
  const uint8_t switchStatus = data[protectionOffset + 3];
  telemetry.dischargingEnabled = (switchStatus & 0x01) != 0;
  telemetry.chargingEnabled = (switchStatus & 0x02) != 0;

  const uint8_t alarmEvent1 = data[alarmOffset + 0];
  const uint8_t alarmEvent2 = data[alarmOffset + 1];
  const uint8_t alarmEvent3 = data[alarmOffset + 2];
  const uint8_t alarmEvent4 = data[alarmOffset + 3];
  telemetry.errorsBitmask = static_cast<uint32_t>(alarmEvent1) | (static_cast<uint32_t>(alarmEvent2) << 8) |
                             (static_cast<uint32_t>(alarmEvent3) << 16) |
                             (static_cast<uint32_t>(alarmEvent4) << 24);

  telemetry.valid = true;
  return true;
}

}  // namespace jkbmsr
