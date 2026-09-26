#pragma once
// Minimal WebServer host shim — NOT the arduino-esp32 WebServer.
//
// Why: provisioning/CaptivePortal.h embeds a WebServer by value and
// CaptivePortal.cpp registers routes on it, so the suite cannot even *compile*
// the SoftAP-password helpers without the type. Only the declaration surface is
// needed: the host run never calls begin()/handleClient(), and the portal tests
// exercise CaptivePortal's static helpers, not its HTTP handlers. Every method
// below is therefore an inert no-op — this stub proves the portal compiles, it
// does not test the portal.
//
// This is a test scaffold only. It must never be on the include path for a real
// firmware build.

#include <functional>

#include <Arduino.h>  // String

enum HTTP_Method : uint8_t {
  HTTP_ANY,
  HTTP_GET,
  HTTP_HEAD,
  HTTP_POST,
  HTTP_PUT,
  HTTP_PATCH,
  HTTP_DELETE,
  HTTP_OPTIONS,
};

class WebServer {
 public:
  using THandlerFunction = std::function<void(void)>;
  using THandlerFunctionArg = std::function<void(const String&)>;

  explicit WebServer(uint16_t port) : port_(port) {}
  virtual ~WebServer() = default;

  void begin() {}
  void stop() {}
  void handleClient() {}

  void on(const String& uri, HTTP_Method method, THandlerFunction handler) {
    (void)uri;
    (void)method;
    (void)handler;
  }
  void on(const char* uri, HTTP_Method method, THandlerFunction handler) {
    on(String(uri), method, handler);
  }
  void onNotFound(THandlerFunction handler) { (void)handler; }

  // Both arities the core exposes, and neither with default arguments: a
  // defaulted 3-arg send() would make send(303) ambiguous with send(int).
  void send(int code) { (void)code; }
  void send(int code, const char* contentType, const String& content) {
    (void)code;
    (void)contentType;
    (void)content;
  }
  void sendHeader(const String& name, const String& value, bool first = false) {
    (void)name;
    (void)value;
    (void)first;
  }

  // Always false: nothing is ever listening, so every guard in the portal's
  // POST /save handler reads as "request did not come from the setup page".
  bool hasArg(const String& name) const {
    (void)name;
    return false;
  }
  String arg(const String& name) const {
    (void)name;
    return String();
  }

 private:
  uint16_t port_;
};
