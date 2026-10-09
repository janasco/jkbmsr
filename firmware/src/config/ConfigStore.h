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
  // Opaque revision of the last remote Wi-Fi target this gateway applied
  // (server-side device_wifi_configs.desired_revision). The gateway persists
  // it and re-applies a target only when /device/config delivers a different
  // value, so a steady poll does not restart the gateway.
  String wifiDesiredRevision;
  // True when the current credentials came from the LOCAL provisioning path
  // (Improv Serial / captive portal) rather than a cloud push, and the flag
  // has not yet been reported to the cloud. Cleared after a successful report.
  // Lets the backend yield a stale remote target to a person who fixed the
  // device on site (see backend services/wifiConfigs.ts).
  bool wifiLocalProvisioned = false;
  // Consecutive boots where joining the saved network failed. Persisted so the
  // restart loop can periodically open the local AP instead of rebooting
  // forever with no human access. Reset on a successful connection.
  uint32_t wifiRestartCount = 0;
  // Per-device claim secret, minted on first boot. Handed to the browser after
  // Wi-Fi provisioning and required by the backend to bind this device to a
  // user account (anti-spoof; see docs/phase1-provisioning-spec.md).
  String claimCode;
  // Account-bound claim token, written over USB/Improv by the web flasher while
  // the owner is signed in (Improv command SetClaimToken). Presented once on
  // FIRST registration (POST /device/register) so the gateway binds itself to
  // that account, then cleared. Empty on devices flashed before this existed or
  // when the token never reached the device — the claim-code path above still
  // works in that case.
  String claimToken;
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
