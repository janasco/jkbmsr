#include "JbdBmsParser.h"

#include <string.h>

#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameStart = 0xDD;
constexpr uint8_t kFrameEnd = 0x77;
constexpr uint8_t kCmdRead = 0xA5;
constexpr size_t kMaxTemperatureSensors = 6;

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint32_t readU32(const uint8_t* p) {
  return (static_cast<uint32_t>(readU16(p)) << 16) | readU16(p + 2);
}

// JBD's checksum is the two's-complement negation of the byte sum (wrapping
// in 16 bits), computed over the status/length/data span of a response (or
// address/length/data span of a request).
uint16_t frameChecksum(const uint8_t* data, size_t length) {
  uint16_t checksum = 0;
  for (size_t index = 0; index < length; ++index) {
    checksum = static_cast<uint16_t>(checksum - data[index]);
  }
  return checksum;
}

}  // namespace

void JbdBmsParser::begin(Stream& serial) {
  serial_ = &serial;
}

void JbdBmsParser::setRawCaptureEnabled(bool enabled) {
  status_.rawCaptureEnabled = enabled;
}

BmsUartStatus JbdBmsParser::status() const {
  return status_;
}

void JbdBmsParser::sendReadCommand(uint8_t address) {
  uint8_t frame[7];
  frame[0] = kFrameStart;
  frame[1] = kCmdRead;
  frame[2] = address;
  frame[3] = 0x00;  // request data length: reads carry no payload
  const uint16_t checksum = frameChecksum(frame + 2, 2);
  frame[4] = static_cast<uint8_t>(checksum >> 8);
  frame[5] = static_cast<uint8_t>(checksum);
  frame[6] = kFrameEnd;
  serial_->write(frame, sizeof(frame));
  serial_->flush();
}

size_t JbdBmsParser::receiveFrame(uint8_t* buffer) {
  size_t length = 0;
  const uint32_t startedAtMs = millis();
  while (millis() - startedAtMs < kFrameTimeoutMs) {
    while (serial_->available() > 0 && length < kBufferSize) {
      const int value = serial_->read();
      if (value < 0) {
        break;
      }
      if (length == 0 && static_cast<uint8_t>(value) != kFrameStart) {
        continue;  // resync on the start byte
      }
      buffer[length++] = static_cast<uint8_t>(value);
      status_.bytesReceived += 1;

      if (length >= 4) {
        const size_t dataLen = buffer[3];
        const size_t frameLen = 4 + dataLen + 3;
        if (frameLen > kBufferSize) {
          length = 0;  // corrupt length field; resync
          continue;
        }
        if (length >= frameLen) {
          return frameLen;
        }
      }
    }
    delay(2);
  }
  return 0;
}

bool JbdBmsParser::poll(BatteryTelemetry& telemetry) {
  if (serial_ == nullptr) {
    logWarn("JBD-BMS UART parser is not initialized");
    return false;
  }

  telemetry.valid = false;
  telemetry.source = "uart";
  telemetry.capturedAtMs = millis();

  uint8_t buffer[kBufferSize];
  uint8_t successCount = 0;

  sendReadCommand(kCmdHardwareInfo);
  size_t frameLen = receiveFrame(buffer);
  if (frameLen > 0) {
    emitBmsRawCapture("JKBMSR_JBD_UART_FRAME", buffer, frameLen, status_.rawCaptureEnabled);
  }
  if (frameLen > 0 && parseFrame(buffer, frameLen, telemetry)) {
    successCount += 1;
  } else {
    status_.parseErrors += 1;
  }

  sendReadCommand(kCmdCellInfo);
  frameLen = receiveFrame(buffer);
  if (frameLen > 0) {
    emitBmsRawCapture("JKBMSR_JBD_UART_FRAME", buffer, frameLen, status_.rawCaptureEnabled);
  }
  if (frameLen > 0 && parseFrame(buffer, frameLen, telemetry)) {
    successCount += 1;
  } else {
    status_.parseErrors += 1;
  }

  if (successCount == 0) {
    return false;
  }

  telemetry.valid = true;
  telemetry.capturedAtMs = millis();
  status_.lastFrameAtMs = telemetry.capturedAtMs;
  return true;
}

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
