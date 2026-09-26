#pragma once

#include <Arduino.h>

#include "HardwareProfile.h"

namespace jkbmsr {

struct DeviceConfig {
  String deviceId;
  String wifiSsid;
  String wifiPassword;
  String deviceToken;
  String deviceSecret;
  // Per-device claim secret, minted on first boot. Handed to the browser after
  // Wi-Fi provisioning and required by the backend to bind this device to a
  // user account (anti-spoof; see docs/phase1-provisioning-spec.md).
  String claimCode;
  // Highest firmware version this device has ever run. OTA refuses anything
  // not strictly newer than this (anti-rollback). Persisted in NVS.
  String firmwareVersionFloor;
  uint32_t telemetryIntervalMs = 60000;
  bool otaEnabled = true;
  // "jk" | "daly" | "jbd" — selects which BmsUartClient main.cpp polls.
  // Defaults to "jk" so every already-deployed gateway keeps working
  // unchanged.
  String bmsVendor = "jk";
  int bmsUartRxPin = kDefaultBmsRxPin;
  int bmsUartTxPin = kDefaultBmsTxPin;
  uint32_t bmsUartBaudRate = 115200;
  bool bmsUartCaptureEnabled = false;
  // When enabled with a MAC address, telemetry is read over BLE (JK02
  // protocol) instead of the UART-TTL link.
  bool bmsBleEnabled = false;
  String bmsBleAddress;

  // True once Wi-Fi credentials have been provisioned. When false the device
  // enters provisioning mode instead of failing to connect silently.
  bool wifiConfigured() const { return wifiSsid.length() > 0; }
};

class ConfigStore {
 public:
  bool begin();
  DeviceConfig load();
  bool save(const DeviceConfig& config);
};

}  // namespace jkbmsr
