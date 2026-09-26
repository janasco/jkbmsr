#include "CaptivePortal.h"

#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266WiFi.h>
#else
#include <WiFi.h>
#include <esp_random.h>
#endif

#include "ProvisioningManager.h"

namespace jkbmsr {

namespace {

constexpr byte kDnsPort = 53;
const IPAddress kApIp(192, 168, 4, 1);
const IPAddress kApGateway(192, 168, 4, 1);
const IPAddress kApSubnet(255, 255, 255, 0);

// Hardware RNG, same source DeviceIdentity::generateClaimCode() uses. It is
// file-local there, so mirror the platform split rather than widening that
// anonymous namespace's reach.
uint32_t hardwareRandomWord() {
#if defined(ARDUINO_ARCH_ESP8266)
  return ESP.random();
#else
  return esp_random();
#endif
}

String htmlEscape(const String& input) {  String out;
  out.reserve(input.length());
  for (size_t i = 0; i < input.length(); ++i) {
    const char c = input[i];
    switch (c) {
      case '&':
        out += "&amp;";
        break;
      case '<':
        out += "&lt;";
        break;
      case '>':
        out += "&gt;";
        break;
      case '"':
        out += "&quot;";
        break;
      default:
        out += c;
        break;
    }
  }
  return out;
}

}  // namespace

String CaptivePortal::softApSsid(const String& deviceId) {
  String suffix = deviceId;
  if (suffix.length() > 4) {
    suffix = suffix.substring(suffix.length() - 4);
  }
  suffix.toUpperCase();
  return "JKBMSR-Setup-" + suffix;
}

String CaptivePortal::softApPassword(const String& deviceId, const String& claimCode) {
  // Same ambiguity-free alphabet as the claim code, widened to 16 symbols so
  // the passphrase lands in WPA2's 8..63 character range.
  static const char kAlphabet[] = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  constexpr size_t kAlphabetSize = sizeof(kAlphabet) - 1;
  constexpr size_t kPassphraseLength = 16;

  // FNV-1a, run over deviceId + claimCode so two devices that somehow shared a
  // claim code still get different passphrases. This is a key-stretch, not a
  // cryptographic hash: the input is a 40-bit secret and the output cannot
  // exceed that, which is acceptable for the threat model documented in the
  // header (an attacker must be physically nearby to capture a WPA2 handshake,
  // and only during the provisioning window).
  uint32_t hash = 2166136261UL;
  const String material = deviceId + "|" + claimCode;
  for (size_t i = 0; i < material.length(); ++i) {
    hash ^= static_cast<uint8_t>(material[i]);
    hash *= 16777619UL;
  }
  // Avalanche so each output symbol depends on the whole hash, then emit.
  uint32_t state = hash;
  String passphrase;
  passphrase.reserve(kPassphraseLength);
  for (size_t i = 0; i < kPassphraseLength; ++i) {
    // xorshift32
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    passphrase += kAlphabet[state % kAlphabetSize];
  }
  return passphrase;
}

String CaptivePortal::newSessionToken() {
  // 16 hex symbols = 64 bits from the hardware RNG. Long enough that a
  // drive-by client cannot guess it; it only has to survive the few seconds
  // the setup page is open.
  String token;
  token.reserve(16);
  for (size_t i = 0; i < 16; ++i) {
    const uint32_t r = hardwareRandomWord();
    const char hex[] = "0123456789abcdef";
    token += hex[(r >> 4) & 0x0F];
    token += hex[r & 0x0F];
  }
  return token;
}

void CaptivePortal::begin(const String& deviceId, const String& claimCode) {
  end();

  deviceId_ = deviceId;
  claimCode_ = claimCode;
  onboardUrl_ = buildOnboardUrl(deviceId, claimCode);
  sessionToken_ = newSessionToken();
  done_ = false;
  flashMessage_ = "";
  flashSuccess_ = false;

  // AP+STA so we can verify submitted credentials against the target network
  // without tearing down the portal mid-attempt.
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(kApIp, kApGateway, kApSubnet);
  const String apSsid = softApSsid(deviceId);
  const String apPassword = softApPassword(deviceId, claimCode);
  WiFi.softAP(apSsid.c_str(), apPassword.c_str());

  dns_.start(kDnsPort, "*", kApIp);
  if (!routesRegistered_) {
    registerRoutes();
    routesRegistered_ = true;
  }
  server_.begin();
  active_ = true;
}

void CaptivePortal::end() {
  if (!active_) {
    return;
  }
  server_.stop();
  dns_.stop();
  WiFi.softAPdisconnect(true);
  // Drop back to station-only; any successful STA association from /save is
  // preserved across softAPdisconnect.
  if (WiFi.status() == WL_CONNECTED) {
    WiFi.mode(WIFI_STA);
  }
  active_ = false;
  tryConnect_ = nullptr;
  scanNetworks_ = nullptr;
  outSsid_ = nullptr;
  outPassword_ = nullptr;
}

bool CaptivePortal::poll(const ConnectFn& tryConnect, const ScanFn& scanNetworks, String& outSsid, String& outPassword) {
  if (!active_ || done_) {
    return done_;
  }

  tryConnect_ = tryConnect;
  scanNetworks_ = scanNetworks;
  outSsid_ = &outSsid;
  outPassword_ = &outPassword;

  dns_.processNextRequest();
  server_.handleClient();

  tryConnect_ = nullptr;
  scanNetworks_ = nullptr;
  outSsid_ = nullptr;
  outPassword_ = nullptr;
  return done_;
}

void CaptivePortal::registerRoutes() {
  server_.on("/", HTTP_GET, [this]() { handleRoot(); });
  server_.on("/scan", HTTP_GET, [this]() { handleScan(); });
  server_.on("/save", HTTP_POST, [this]() { handleSave(); });
  // Common captive-portal detection endpoints — serve the setup page so the
  // phone OS pops the login/portal sheet.
  server_.on("/generate_204", HTTP_GET, [this]() { handleCaptiveProbe(); });
  server_.on("/gen_204", HTTP_GET, [this]() { handleCaptiveProbe(); });
  server_.on("/hotspot-detect.html", HTTP_GET, [this]() { handleCaptiveProbe(); });
  server_.on("/connecttest.txt", HTTP_GET, [this]() { handleCaptiveProbe(); });
  server_.on("/ncsi.txt", HTTP_GET, [this]() { handleCaptiveProbe(); });
  server_.onNotFound([this]() { handleNotFound(); });
}

void CaptivePortal::handleRoot() {
  server_.send(200, "text/html", buildSetupPage(flashMessage_, flashSuccess_));
}

void CaptivePortal::handleScan() {
  // Delegates to the injected scan callback (WifiManager::scan) rather than
  // calling WiFi.scanNetworks() directly. Confirmed on real hardware
  // (2026-08-21): this endpoint used to bypass WifiManager's connecting_
  // guard entirely, so a scan triggered from this page's button could still
  // collide with an in-flight connect attempt from Improv Serial or this
  // same portal's own /save handler, silently failing with "STA is
  // connecting, scan are not allowed" and leaving the network list empty.
  WifiScanResult results[kMaxWifiScanResults];
  const size_t count = scanNetworks_ ? scanNetworks_(results, kMaxWifiScanResults) : 0;
  String json = "[";
  for (size_t i = 0; i < count; ++i) {
    if (i > 0) {
      json += ",";
    }
    String ssid = results[i].ssid;
    ssid.replace("\\", "\\\\");
    ssid.replace("\"", "\\\"");
    json += "{\"ssid\":\"" + ssid + "\",\"rssi\":" + String(results[i].rssi) +
            ",\"secure\":" + String(results[i].secure ? "true" : "false") +
            "}";
  }
  json += "]";
  server_.send(200, "application/json", json);
}

void CaptivePortal::handleSave() {
  // CSRF / drive-by guard. The session token is minted in begin() and only
  // ever leaves the device inside the setup form, so a client that could not
  // join the AP cannot produce a valid one. Check it before doing anything
  // with the submitted credentials.
  if (sessionToken_.length() == 0 || !server_.hasArg("token") ||
      server_.arg("token") != sessionToken_) {
    flashMessage_ = "This setup session expired or the request did not come from "
                    "the setup page. Reload the page and try again.";
    flashSuccess_ = false;
    server_.sendHeader("Location", "/", true);
    server_.send(303);
    return;
  }

  if (!server_.hasArg("ssid")) {
    flashMessage_ = "SSID is required.";
    flashSuccess_ = false;
    server_.sendHeader("Location", "/", true);
    server_.send(303);
    return;
  }

  const String ssid = server_.arg("ssid");
  const String password = server_.hasArg("password") ? server_.arg("password") : "";
  if (ssid.length() == 0) {
    flashMessage_ = "SSID is required.";
    flashSuccess_ = false;
    server_.sendHeader("Location", "/", true);
    server_.send(303);
    return;
  }

  if (!tryConnect_ || !tryConnect_(ssid, password)) {
    flashMessage_ = "Could not connect. Check the password and try again.";
    flashSuccess_ = false;
    server_.sendHeader("Location", "/", true);
    server_.send(303);
    return;
  }

  if (outSsid_ != nullptr) {
    *outSsid_ = ssid;
  }
  if (outPassword_ != nullptr) {
    *outPassword_ = password;
  }
  done_ = true;
  flashMessage_ = "Connected. Continue setup in your browser.";
  flashSuccess_ = true;
  server_.send(200, "text/html", buildSetupPage(flashMessage_, flashSuccess_));
}

void CaptivePortal::handleCaptiveProbe() {
  server_.sendHeader("Location", "http://192.168.4.1/", true);
  server_.send(302, "text/plain", "");
}

void CaptivePortal::handleNotFound() {
  server_.sendHeader("Location", "http://192.168.4.1/", true);
  server_.send(302, "text/plain", "");
}

String CaptivePortal::buildSetupPage(const String& message, bool success) const {
  String page;
  page.reserve(3500);
  page += F(
      "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
      "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
      "<title>JKBMSR Setup</title><style>"
      "body{font-family:system-ui,sans-serif;margin:0;background:#0f1419;color:#e7ecf1;"
      "display:flex;justify-content:center;padding:24px}"
      "main{width:100%;max-width:420px}"
      "h1{font-size:1.4rem;margin:0 0 4px}"
      "p.sub{color:#9aa7b5;margin:0 0 20px}"
      "label{display:block;margin:12px 0 4px;font-size:.9rem;color:#9aa7b5}"
      "input,select,button{width:100%;box-sizing:border-box;padding:12px;border-radius:8px;"
      "border:1px solid #2a3540;background:#1a222b;color:#e7ecf1;font-size:1rem}"
      "button{margin-top:16px;background:#2f6fed;border-color:#2f6fed;font-weight:600}"
      "button.secondary{background:#243040;border-color:#2a3540;margin-top:8px}"
      ".msg{padding:12px;border-radius:8px;margin-bottom:16px}"
      ".msg.ok{background:#14301f;color:#8dffa8}"
      ".msg.err{background:#301414;color:#ffb4b4}"
      "a{color:#8eb6ff}"
      "</style></head><body><main>"
      "<h1>JKBMSR</h1><p class=\"sub\">Connect this device to your Wi-Fi</p>");

  if (message.length() > 0) {
    page += F("<div class=\"msg ");
    page += success ? F("ok") : F("err");
    page += F("\">");
    page += htmlEscape(message);
    page += F("</div>");
  }

  if (success) {
    page += F("<p>Device is online. Open the onboarding link to claim it:</p><p><a href=\"");
    page += htmlEscape(onboardUrl_);
    page += F("\">");
    page += htmlEscape(onboardUrl_);
    page += F("</a></p>");
  } else {
    page += F(
        "<form method=\"POST\" action=\"/save\">"
        "<input type=\"hidden\" name=\"token\" value=\"");
    page += htmlEscape(sessionToken_);
    page += F("\">"
              "<label for=\"ssid\">Network</label>"
        "<input id=\"ssid\" name=\"ssid\" list=\"networks\" autocomplete=\"off\" required>"
        "<datalist id=\"networks\"></datalist>"
        "<label for=\"password\">Password</label>"
        "<input id=\"password\" name=\"password\" type=\"password\">"
        "<button type=\"submit\">Connect</button>"
        "</form>"
        "<button type=\"button\" class=\"secondary\" id=\"scan\">Scan networks</button>"
        "<script>"
        "const list=document.getElementById('networks');"
        "const ssid=document.getElementById('ssid');"
        "document.getElementById('scan').onclick=async()=>{"
        "const btn=document.getElementById('scan');btn.disabled=true;btn.textContent='Scanning…';"
        "try{const r=await fetch('/scan');const nets=await r.json();list.innerHTML='';"
        "nets.sort((a,b)=>b.rssi-a.rssi).forEach(n=>{const o=document.createElement('option');"
        "o.value=n.ssid;list.appendChild(o);});"
        "if(nets[0]&&!ssid.value)ssid.value=nets[0].ssid;"
        "}catch(e){}btn.disabled=false;btn.textContent='Scan networks';};"
        "</script>");
  }

  page += F("<p class=\"sub\" style=\"margin-top:24px\">Device ");
  page += htmlEscape(deviceId_);
  page += F("</p></main></body></html>");
  return page;
}

}  // namespace jkbmsr
