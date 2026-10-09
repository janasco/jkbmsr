#pragma once

#include <Arduino.h>

#include <functional>

#include "provisioning/ImprovProtocol.h"

namespace jkbmsr {

// Builds the URL the browser flasher is redirected to once Wi-Fi provisioning
// succeeds, deep-linking the user straight into claiming the device:
//   https://web.jkbmsr.com/onboard?device=<deviceId>&code=<claimCode>
// Kept as a free function so it can be unit-tested without hardware.
String buildOnboardUrl(const String& deviceId, const String& claimCode);

// Drives the Improv Serial provisioning handshake over a Stream (normally the
// USB Serial the browser flasher is attached to). Non-blocking: pump poll()
// from a loop. The actual Wi-Fi connection attempt is injected as a callback so
// this class carries no WiFi.h dependency and stays native-testable.
class ProvisioningManager {
 public:
  struct Network {
    String ssid;
    int32_t rssi = -127;
    bool secure = true;
  };

  using ConnectFn = std::function<bool(const String& ssid, const String& password)>;
  using ScanFn = std::function<size_t(Network* networks, size_t capacity)>;
  // Invoked when the host hands the gateway an account-bound claim token over
  // Improv (command SetClaimToken). The caller persists it; this class carries
  // no ConfigStore/NVS dependency so it stays native-testable.
  using ClaimTokenFn = std::function<void(const String& token)>;

  // deviceId/claimCode are echoed back to the browser (device info + redirect
  // URL). Safe to call again to restart a session.
  void begin(
      Stream& io,
      const String& deviceId,
      const String& claimCode,
      bool announceReady = true,
      bool claimReady = false);

  // Reads any available bytes and advances the handshake. Returns true exactly
  // once, when credentials have been received AND tryConnect() succeeded, with
  // outSsid/outPassword filled in for the caller to persist. onClaimToken, when
  // supplied, is called for every valid SetClaimToken command so the caller can
  // persist the account binding.
  bool poll(
      const ConnectFn& tryConnect,
      String& outSsid,
      String& outPassword,
      const ScanFn& scanNetworks = {},
      const ClaimTokenFn& onClaimToken = {});

  improv::State state() const { return state_; }

 private:
  void sendCurrentState(improv::State state);
  void sendError(improv::Error error);
  void sendRpcResult(improv::Command command, const String* strings, size_t count);
  void sendDeviceInfo();
  void sendWifiNetworks(const ScanFn& scanNetworks);
  void handleWifiSettings(const uint8_t* cmdData, uint8_t cmdLen, const ConnectFn& tryConnect,
                          String& outSsid, String& outPassword, bool& done);

  Stream* io_ = nullptr;
  String deviceId_;
  String claimCode_;
  improv::Parser parser_;
  improv::State state_ = improv::State::Ready;
  bool announced_ = false;
  bool claimReady_ = false;
};

}  // namespace jkbmsr
