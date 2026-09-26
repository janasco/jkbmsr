#include "DalyBmsParser.h"

#include <string.h>

#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0xA5;
constexpr uint8_t kHostAddress = 0x40;
constexpr uint8_t kDataLength = 0x08;

constexpr uint8_t kCmdPackMeasurements = 0x90;
constexpr uint8_t kCmdMinMaxCellVoltage = 0x91;
constexpr uint8_t kCmdMinMaxTemperature = 0x92;
constexpr uint8_t kCmdMosStatus = 0x93;
constexpr uint8_t kCmdStatusInfo = 0x94;

uint8_t frameChecksum(const uint8_t* data, size_t length) {
  uint8_t checksum = 0;
  for (size_t index = 0; index < length; ++index) {
    checksum += data[index];
  }
  return checksum;
}

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

}  // namespace

void DalyBmsParser::begin(Stream& serial) {
  serial_ = &serial;
}

void DalyBmsParser::setRawCaptureEnabled(bool enabled) {
  status_.rawCaptureEnabled = enabled;
}

BmsUartStatus DalyBmsParser::status() const {
  return status_;
}

void DalyBmsParser::sendCommand(uint8_t command) {
  uint8_t frame[kFrameSize];
  frame[0] = kFrameStart;
  frame[1] = kHostAddress;
  frame[2] = command;
  frame[3] = kDataLength;
  memset(frame + 4, 0, 8);
  frame[12] = frameChecksum(frame, 12);
  serial_->write(frame, sizeof(frame));
  serial_->flush();
}

bool DalyBmsParser::receiveFrame(uint8_t* buffer) {
  size_t length = 0;
  const uint32_t startedAtMs = millis();
  while (millis() - startedAtMs < kFrameTimeoutMs) {
    while (serial_->available() > 0 && length < kFrameSize) {
      const int value = serial_->read();
      if (value < 0) {
        break;
      }
      // Resync: a fixed-size frame with no wrapper delimiter other than its
      // own start byte, so a stray leftover byte from a previous timeout
      // could otherwise misalign every field for the rest of this frame.
      if (length == 0 && static_cast<uint8_t>(value) != kFrameStart) {
        continue;
      }
      buffer[length++] = static_cast<uint8_t>(value);
      status_.bytesReceived += 1;
    }
    if (length >= kFrameSize) {
      return true;
    }
    delay(2);
  }
  return false;
}

bool DalyBmsParser::poll(BatteryTelemetry& telemetry) {
  if (serial_ == nullptr) {
    logWarn("Daly-BMS UART parser is not initialized");
    return false;
  }

  telemetry.valid = false;
  telemetry.source = "uart";
  telemetry.capturedAtMs = millis();

  static const uint8_t kCommands[] = {kCmdPackMeasurements, kCmdMinMaxCellVoltage, kCmdMinMaxTemperature,
                                       kCmdMosStatus, kCmdStatusInfo};
  uint8_t successCount = 0;
  for (uint8_t command : kCommands) {
    sendCommand(command);
    uint8_t frame[kFrameSize];
    if (!receiveFrame(frame)) {
      status_.parseErrors += 1;
      continue;
    }
    emitBmsRawCapture("JKBMSR_DALY_UART_FRAME", frame, kFrameSize, status_.rawCaptureEnabled);
    if (parseFrame(frame, kFrameSize, command, telemetry)) {
      successCount += 1;
    } else {
      status_.parseErrors += 1;
    }
  }

  if (successCount == 0) {
    return false;
  }

  telemetry.valid = true;
  telemetry.capturedAtMs = millis();
  status_.lastFrameAtMs = telemetry.capturedAtMs;
  return true;
}

bool DalyBmsParser::parseFrame(const uint8_t* frame, size_t length, uint8_t expectedCommand,
                                BatteryTelemetry& telemetry) {
  if (frame == nullptr || length != kFrameSize) {
    return false;
  }
  if (frame[0] != kFrameStart || frame[2] != expectedCommand || frame[3] != kDataLength) {
    return false;
  }
  if (frameChecksum(frame, 12) != frame[12]) {
    return false;
  }

  const uint8_t* d = frame + 4;  // 8 data bytes
  switch (expectedCommand) {
    case kCmdPackMeasurements:
      // 0x90: voltage (0.1V), current (0.1A, 30000-unit offset), SOC (0.1%).
      telemetry.packVoltage = static_cast<float>(readU16(d)) * 0.1f;
      telemetry.packCurrent = (static_cast<float>(readU16(d + 4)) - 30000.0f) * 0.1f;
      telemetry.stateOfCharge = static_cast<float>(readU16(d + 6)) * 0.1f;
      telemetry.power = telemetry.packVoltage * telemetry.packCurrent;
      return true;
    case kCmdMinMaxCellVoltage: {
      // 0x91: max/min individual cell voltage (mV) and which cell reported it.
      const float maxCellV = static_cast<float>(readU16(d)) * 0.001f;
      const uint8_t maxCell = d[2];
      const float minCellV = static_cast<float>(readU16(d + 3)) * 0.001f;
      const uint8_t minCell = d[5];
      telemetry.maxCellVoltage = maxCellV;
      telemetry.minCellVoltage = minCellV;
      telemetry.maxVoltageCell = maxCell;
      telemetry.minVoltageCell = minCell;
      telemetry.deltaCellVoltage = maxCellV - minCellV;
      // Not decoded in this pilot (would need the multi-frame 0x95 command):
      // approximate rather than leave at zero, which would read as "0V pack".
      telemetry.avgCellVoltage = (maxCellV + minCellV) / 2.0f;
      return true;
    }
    case kCmdMinMaxTemperature:
      // 0x92: min/max temperature sensor reading, 40-unit offset to avoid negatives.
      telemetry.temperature1 = static_cast<float>(d[0]) - 40.0f;
      telemetry.temperature2 = static_cast<float>(d[2]) - 40.0f;
      return true;
    case kCmdMosStatus:
      // 0x93: charge/discharge FET state and residual capacity (mAh).
      telemetry.chargingEnabled = d[1] != 0;
      telemetry.dischargingEnabled = d[2] != 0;
      telemetry.remainingCapacityAh =
          static_cast<float>((static_cast<uint32_t>(d[4]) << 24) | (static_cast<uint32_t>(d[5]) << 16) |
                              (static_cast<uint32_t>(d[6]) << 8) | static_cast<uint32_t>(d[7])) *
          0.001f;
      return true;
    case kCmdStatusInfo:
      // 0x94: cell count (informational only — see class comment on why
      // BatteryTelemetry.cellCount is left at 0), temp sensor count, cycles.
      telemetry.temperatureSensorCount = d[1];
      telemetry.cycleCount = readU16(d + 5);
      return true;
    default:
      return false;
  }
}

}  // namespace jkbmsr
