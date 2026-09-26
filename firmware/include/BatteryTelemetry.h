#pragma once

#include <Arduino.h>

namespace jkbmsr {

constexpr uint8_t kMaxCellCount = 32;
constexpr uint8_t kMaxBleCandidateCount = 5;

struct BatteryTelemetry {
  float packVoltage = 0.0f;
  float packCurrent = 0.0f;
  float stateOfCharge = 0.0f;
  float power = 0.0f;
  float temperature1 = 0.0f;
  float temperature2 = 0.0f;
  float mosfetTemperature = 0.0f;
  float cellVoltages[kMaxCellCount] = {};
  uint8_t cellCount = 0;
  // Balance-lead resistance per cell, in Ohms. JK02 BLE only (0.0 on every
  // slot for UART/other sources — no known way to request it there); zero
  // for any slot at or past cellCount, same convention as cellVoltages.
  float wireResistanceOhms[kMaxCellCount] = {};
  float minCellVoltage = 0.0f;
  float maxCellVoltage = 0.0f;
  float avgCellVoltage = 0.0f;
  float deltaCellVoltage = 0.0f;
  uint8_t minVoltageCell = 0;
  uint8_t maxVoltageCell = 0;
  uint8_t temperatureSensorCount = 0;
  uint32_t cycleCount = 0;
  float cycleCapacityAh = 0.0f;
  float fullCapacityAh = 0.0f;
  float remainingCapacityAh = 0.0f;
  // 0-100 where reported (BLE JK02); 0xFF = not available on this transport.
  uint8_t stateOfHealth = 0xFF;
  uint32_t errorsBitmask = 0;
  bool chargingEnabled = false;
  bool dischargingEnabled = false;
  bool balancingActive = false;
  float balancingCurrent = 0.0f;
  String bmsSoftwareVersion;
  uint8_t protocolVersion = 0;
  // "uart" or "ble" — which link produced this sample.
  const char* source = "uart";
  uint32_t capturedAtMs = 0;
  uint32_t parserLastFrameAtMs = 0;
  uint32_t parserParseErrors = 0;
  uint32_t parserBytesReceived = 0;
  uint32_t parserStaleBytes = 0;
  bool parserRawCaptureEnabled = false;
  uint32_t otaLastCheckAtMs = 0;
  bool otaLastCheckSucceeded = false;
  bool otaUpdateAvailable = false;
  bool otaUpdateApplied = false;
  String otaOfferedVersion;
  String otaLastResult = "idle";
  String bleState = "disabled";
  String bleAddress;
  String bleAdvertisedName;
  String bleHardwareVersion;
  String bleSoftwareVersion;
  int bleRssi = -128;
  uint8_t bleAddressType = 0;
  uint32_t bleFramesDecoded = 0;
  uint32_t bleChecksumErrors = 0;
  uint32_t bleLastFrameAtMs = 0;
  uint32_t bleLastScanAtMs = 0;
  uint32_t bleLastConnectedAtMs = 0;
  String bleLastError;
  bool bleReadOnly = true;
  String bleCandidateAddresses[kMaxBleCandidateCount];
  String bleCandidateNames[kMaxBleCandidateCount];
  int bleCandidateRssi[kMaxBleCandidateCount] = {};
  uint8_t bleCandidateAddressTypes[kMaxBleCandidateCount] = {};
  uint8_t bleCandidateCount = 0;
  bool valid = false;
};

}  // namespace jkbmsr
