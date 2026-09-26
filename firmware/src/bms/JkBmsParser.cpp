#include "JkBmsParser.h"

#include <string.h>

#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint8_t kFrameHeader0 = 0x4E;
constexpr uint8_t kFrameHeader1 = 0x57;
constexpr uint8_t kCommandReadAllRegisters = 0x06;
constexpr uint8_t kFrameSourceGps = 0x02;
constexpr uint8_t kFrameEnd = 0x68;
// Register data begins after the 11-byte response header
// (header 2 + length 2 + terminal 4 + command 1 + source 1 + type 1).
constexpr size_t kDataOffset = 11;
// Fixed span of the register block that follows the variable-length 0x79
// cell-voltage block, through the 0xC0 protocol-version register (matches the
// reference implementation's minimum-length guard).
constexpr size_t kFixedRegisterSpan = 223;

uint16_t readU16(const uint8_t* p) {
  return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

uint32_t readU32(const uint8_t* p) {
  return (static_cast<uint32_t>(readU16(p)) << 16) | readU16(p + 2);
}

// Additive 16-bit checksum over the frame, compared against the big-endian
// trailer.
uint16_t frameChecksum(const uint8_t* data, size_t length) {
  uint16_t checksum = 0;
  for (size_t index = 0; index < length; ++index) {
    checksum += data[index];
  }
  return checksum;
}

// Temperatures are unsigned with 0..100 mapping to 0..100 °C and values above
// 100 encoding negatives (101 = -1 °C, 140 = -40 °C).
float decodeTemperature(uint16_t value) {
  if (value > 100) {
    return static_cast<float>(100 - static_cast<int32_t>(value));
  }
  return static_cast<float>(value);
}

// Protocol version 1 (every model with software >= 6.0): bit 15 set means
// charging (positive), cleared means discharging (negative); low 15 bits are
// centiamps.
float decodeCurrent(uint16_t raw) {
  const float magnitude = static_cast<float>(raw & 0x7FFF) * 0.01f;
  return (raw & 0x8000) ? magnitude : -magnitude;
}

}  // namespace

void JkBmsParser::begin(Stream& serial) {
  serial_ = &serial;
}

void JkBmsParser::setRawCaptureEnabled(bool enabled) {
  status_.rawCaptureEnabled = enabled;
}

BmsUartStatus JkBmsParser::status() const {
  return status_;
}

void JkBmsParser::sendStatusRequest() {
  // "Read all registers" request as sent by the official GPS/UART accessories.
  uint8_t frame[21];
  frame[0] = kFrameHeader0;
  frame[1] = kFrameHeader1;
  frame[2] = 0x00;  // length high byte
  frame[3] = 0x13;  // length low byte (frame length minus the 2 CRC bytes)
  frame[4] = 0x00;  // BMS terminal number
  frame[5] = 0x00;
  frame[6] = 0x00;
  frame[7] = 0x00;
  frame[8] = kCommandReadAllRegisters;
  frame[9] = kFrameSourceGps;
  frame[10] = 0x00;  // frame type: read data
  frame[11] = 0x00;  // register 0x00: read all
  frame[12] = 0x00;  // record number
  frame[13] = 0x00;
  frame[14] = 0x00;
  frame[15] = 0x00;
  frame[16] = kFrameEnd;
  const uint16_t checksum = frameChecksum(frame, 17);
  frame[17] = 0x00;
  frame[18] = 0x00;
  frame[19] = static_cast<uint8_t>(checksum >> 8);
  frame[20] = static_cast<uint8_t>(checksum);
  serial_->write(frame, sizeof(frame));
  serial_->flush();
}

void JkBmsParser::resyncBuffer(size_t dropAtLeast) {
  size_t start = dropAtLeast;
  while (start + 1 < bufferLength_ &&
         !(buffer_[start] == kFrameHeader0 && buffer_[start + 1] == kFrameHeader1)) {
    ++start;
  }
  if (start + 1 >= bufferLength_) {
    // Keep a trailing 0x4E in case its 0x57 arrives next.
    if (bufferLength_ > 0 && buffer_[bufferLength_ - 1] == kFrameHeader0) {
      buffer_[0] = kFrameHeader0;
      bufferLength_ = 1;
    } else {
      bufferLength_ = 0;
    }
    return;
  }
  if (start > 0) {
    memmove(buffer_, buffer_ + start, bufferLength_ - start);
    bufferLength_ -= start;
  }
}

bool JkBmsParser::poll(BatteryTelemetry& telemetry) {
  if (serial_ == nullptr) {
    logWarn("JK-BMS UART parser is not initialized");
    return false;
  }

  telemetry.valid = false;
  telemetry.capturedAtMs = millis();

  // Drop bytes from a previous, abandoned exchange — but count and capture
  // them: a late response landing here is the key debugging signal.
  {
    uint8_t staleBuffer[64] = {};
    size_t staleLength = 0;
    while (serial_->available() > 0) {
      const int value = serial_->read();
      if (value < 0) {
        break;
      }
      status_.staleBytes += 1;
      if (staleLength < sizeof(staleBuffer)) {
        staleBuffer[staleLength++] = static_cast<uint8_t>(value);
      }
    }
    if (staleLength > 0) {
      emitRawCapture("JKBMSR_UART_STALE", staleBuffer, staleLength);
    }
  }
  bufferLength_ = 0;

  sendStatusRequest();

  bool parsed = false;
  const uint32_t startedAtMs = millis();
  while (millis() - startedAtMs < kResponseTimeoutMs) {
    while (serial_->available() > 0 && bufferLength_ < kBufferSize) {
      const int value = serial_->read();
      if (value < 0) {
        break;
      }
      buffer_[bufferLength_++] = static_cast<uint8_t>(value);
      status_.bytesReceived += 1;
    }

    resyncBuffer(0);

    if (bufferLength_ >= 4) {
      const size_t frameLength = static_cast<size_t>(readU16(buffer_ + 2)) + 2;
      if (frameLength < 21 || frameLength > kBufferSize) {
        // Corrupt length; drop this header and resync on the next one.
        emitRawCapture("JKBMSR_UART_BADLEN", buffer_, bufferLength_ < 64 ? bufferLength_ : 64);
        status_.parseErrors += 1;
        resyncBuffer(2);
        continue;
      }
      if (bufferLength_ >= frameLength) {
        emitRawCapture("JKBMSR_UART_FRAME", buffer_, frameLength);
        if (parseFrame(buffer_, frameLength, telemetry)) {
          telemetry.capturedAtMs = millis();
          status_.lastFrameAtMs = telemetry.capturedAtMs;
          bufferLength_ = 0;
          parsed = true;
          break;
        }
        status_.parseErrors += 1;
        resyncBuffer(2);
        continue;
      }
    }

    delay(5);
  }

  // Whatever partial data is left when the window closes is the other key
  // signal (wrong baud shows as garbage, a short reply as a stub frame).
  if (!parsed && bufferLength_ > 0) {
    emitRawCapture("JKBMSR_UART_PARTIAL", buffer_,
                   bufferLength_ < kBufferSize ? bufferLength_ : kBufferSize);
  }
  return parsed;
}

bool JkBmsParser::parseFrame(const uint8_t* frame, size_t length, BatteryTelemetry& telemetry) {
  if (frame == nullptr || length < kDataOffset + 2) {
    return false;
  }
  if (frame[0] != kFrameHeader0 || frame[1] != kFrameHeader1) {
    return false;
  }

  const size_t declaredLength = readU16(frame + 2);
  if (declaredLength + 2 != length) {
    return false;
  }
  const uint16_t computedChecksum = frameChecksum(frame, declaredLength);
  const uint16_t remoteChecksum = readU16(frame + declaredLength);
  if (computedChecksum != remoteChecksum) {
    return false;
  }
  if (frame[8] != kCommandReadAllRegisters) {
    return false;
  }

  // d points at the register data; d[0] is the 0x79 cell-voltage register.
  const uint8_t* d = frame + kDataOffset;
  const size_t dataLength = declaredLength - kDataOffset;
  if (dataLength < 2 || d[0] != 0x79) {
    return false;
  }
  const uint8_t cellBlockBytes = d[1];
  const uint8_t cells = cellBlockBytes / 3;
  if (cells == 0 || cells > kMaxCellCount || cellBlockBytes % 3 != 0) {
    return false;
  }
  if (dataLength < static_cast<size_t>(cellBlockBytes) + kFixedRegisterSpan) {
    return false;
  }

  BatteryTelemetry parsed;
  parsed.source = "uart";
  parsed.cellCount = cells;
  parsed.minCellVoltage = 100.0f;
  parsed.maxCellVoltage = -100.0f;
  for (uint8_t cell = 0; cell < cells; ++cell) {
    const uint8_t* entry = d + 2 + static_cast<size_t>(cell) * 3;
    const uint8_t cellIndex = entry[0];
    if (cellIndex == 0 || cellIndex > cells) {
      return false;
    }
    const float voltage = static_cast<float>(readU16(entry + 1)) * 0.001f;
    parsed.cellVoltages[cellIndex - 1] = voltage;
    parsed.avgCellVoltage += voltage;
    if (voltage < parsed.minCellVoltage) {
      parsed.minCellVoltage = voltage;
      parsed.minVoltageCell = cellIndex;
    }
    if (voltage > parsed.maxCellVoltage) {
      parsed.maxCellVoltage = voltage;
      parsed.maxVoltageCell = cellIndex;
    }
  }
  parsed.avgCellVoltage /= cells;
  parsed.deltaCellVoltage = parsed.maxCellVoltage - parsed.minCellVoltage;

  // Registers after the cell block sit at fixed offsets: `base` is the first
  // byte after the 0x79 block; each 3-byte register is tag + 16-bit value.
  const uint8_t* base = d + cellBlockBytes + 3;

  // 0x80/0x81/0x82: MOS, sensor 1, sensor 2 temperatures.
  parsed.mosfetTemperature = decodeTemperature(readU16(base + 3 * 0));
  parsed.temperature1 = decodeTemperature(readU16(base + 3 * 1));
  parsed.temperature2 = decodeTemperature(readU16(base + 3 * 2));
  // 0x83: total voltage, 0.01 V.
  parsed.packVoltage = static_cast<float>(readU16(base + 3 * 3)) * 0.01f;
  // 0x84: current (protocol v1 sign-bit encoding), 0.01 A.
  parsed.packCurrent = decodeCurrent(readU16(base + 3 * 4));
  // 0x85: state of charge, single byte percent.
  parsed.stateOfCharge = static_cast<float>(base[15]);
  // 0x86: number of battery temperature sensors.
  parsed.temperatureSensorCount = base[17];
  // 0x87: cycle count.
  parsed.cycleCount = readU16(base + 19);
  // 0x89: total cycle capacity, Ah (32-bit).
  parsed.cycleCapacityAh = static_cast<float>(readU32(base + 22));
  // 0x8B: warning bitmask.
  parsed.errorsBitmask = readU16(base + 30);
  // 0x8C: status bitmask — bit 0 charging, bit 1 discharging, bit 2 balancing.
  const uint16_t statusBitmask = readU16(base + 33);
  parsed.chargingEnabled = (statusBitmask & 0x0001) != 0;
  parsed.dischargingEnabled = (statusBitmask & 0x0002) != 0;
  parsed.balancingActive = (statusBitmask & 0x0004) != 0;
  // 0xAA: nominal capacity setting, Ah (32-bit).
  parsed.fullCapacityAh = static_cast<float>(readU32(base + 118));
  parsed.remainingCapacityAh = parsed.fullCapacityAh * parsed.stateOfCharge * 0.01f;
  // 0xB7: software version, up to 15 characters.
  char softwareVersion[16] = {};
  memcpy(softwareVersion, base + 171, 15);
  parsed.bmsSoftwareVersion = String(softwareVersion);
  // 0xC0: protocol version.
  parsed.protocolVersion = base[219];

  parsed.power = parsed.packVoltage * parsed.packCurrent;
  parsed.valid = true;
  parsed.capturedAtMs = telemetry.capturedAtMs;
  telemetry = parsed;
  return true;
}

void JkBmsParser::emitRawCapture(const char* label, const uint8_t* data, size_t length) const {
  if (!status_.rawCaptureEnabled || data == nullptr || length == 0) {
    return;
  }

  Serial.print(label);
  Serial.print(" ");
  Serial.print(millis());
  Serial.print(" ");
  Serial.print(length);
  Serial.print(" ");
  for (size_t index = 0; index < length; ++index) {
    if (data[index] < 0x10) {
      Serial.print("0");
    }
    Serial.print(data[index], HEX);
    if (index + 1 < length) {
      Serial.print(" ");
    }
  }
  Serial.println();
}

}  // namespace jkbmsr
