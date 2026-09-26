#pragma once

#include <Arduino.h>

#include <DNSServer.h>
#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266WebServer.h>
#else
#include <WebServer.h>
#endif
#include <functional>

#include "network/WifiManager.h"

namespace jkbmsr {

#if defined(ARDUINO_ARCH_ESP8266)
// ESP8266 core's web-server class is named/headered differently from
// arduino-esp32's WebServer, though otherwise largely API-compatible for
// what CaptivePortal uses (route registration, request handling).
using WebServer = ESP8266WebServer;
#endif

// SoftAP captive-portal fallback for field provisioning when USB/Improv is
// unavailable. Raises a WPA2 AP named JKBMSR-Setup-XXXX (XXXX = last 4 of the
// device ID) with a PER-DEVICE password derived from the device's claim code,
// serves a self-contained setup page, and verifies submitted credentials via
// the injected connect callback — the same capture path Improv Serial uses.
//
// Security note: the AP password used to be a global constant published in
// docs/first-device-bringup.md and in the packaging. The SSID embeds the
// device ID, which is not secret (it appears in logs, Improv responses and the
// dashboard), so anyone nearby could join the setup network, read the claim
// code off the success page, and rebind the gateway to their own account — and
// the claim code is the sole anti-spoof factor for device binding per
// docs/hardware-identity-and-license-transfer.md. The password is now derived
// per device and a session token gates POST /save, so a drive-by client can
// neither join the AP nor repoint the gateway.
class CaptivePortal {
 public:
  using ConnectFn = std::function<bool(const String& ssid, const String& password)>;
  using ScanFn = std::function<size_t(WifiScanResult* results, size_t capacity)>;

  // SoftAP SSID built from the trailing characters of deviceId.
  static String softApSsid(const String& deviceId);

  // WPA2 password for this specific device, derived from its claim code.
  //
  // Returns a String rather than a const char* because it is now computed, and
  // because WPA2 passphrases must be 8..63 characters.
  //
  // Entropy: the claim code is 8 symbols from a 32-symbol alphabet (40 bits),
  // so this expands a 40-bit secret into a 16-character passphrase. That is
  // deliberately not a strong secret against an offline WPA2 handshake attack
  // by someone physically nearby — it is chosen over a random-but-unrecorded
  // password because the user can read the claim code off the serial log (and
  // off the device label) after a reflash, whereas a random password stored
  // nowhere is unrecoverable and would strand a user who missed the serial
  // output. To harden further, store a separate random AP secret in NVS and
  // print/label it.
  static String softApPassword(const String& deviceId, const String& claimCode);

  // Unguessable per-session token embedded in the setup form and required on
  // POST /save. Without it any client that can reach the portal can POST
  // credentials and repoint the gateway to a hostile network. 128 bits from
  // the hardware RNG.
  static String newSessionToken();

  void begin(const String& deviceId, const String& claimCode);
  void end();

  // Non-blocking: process DNS + HTTP. Returns true once credentials have been
  // submitted AND tryConnect() succeeded, with outSsid/outPassword filled in.
  // scanNetworks is injected (rather than calling WiFi.scanNetworks()
  // directly from handleScan()) so this class's /scan endpoint shares
  // WifiManager's guard against racing a connect attempt in progress on
  // either this portal or the parallel Improv Serial session -- see
  // WifiManager::scan().
  bool poll(const ConnectFn& tryConnect, const ScanFn& scanNetworks, String& outSsid, String& outPassword);

  bool active() const { return active_; }

 private:
  void registerRoutes();
  void handleRoot();
  void handleScan();
  void handleSave();
  void handleCaptiveProbe();
  void handleNotFound();
  String buildSetupPage(const String& message, bool success) const;

  DNSServer dns_;
#if defined(ARDUINO_ARCH_ESP8266)
  ESP8266WebServer server_{80};
#else
  WebServer server_{80};
#endif
  String deviceId_;
  String claimCode_;
  String onboardUrl_;
  String sessionToken_;
  ConnectFn tryConnect_;
  ScanFn scanNetworks_;
  String* outSsid_ = nullptr;
  String* outPassword_ = nullptr;
  bool active_ = false;
  bool done_ = false;
  bool routesRegistered_ = false;
  String flashMessage_;
  bool flashSuccess_ = false;
};

}  // namespace jkbmsr
