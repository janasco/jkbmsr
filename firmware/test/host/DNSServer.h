#pragma once
// Minimal DNSServer host shim — NOT the arduino-esp32 DNSServer.
//
// Why: provisioning/CaptivePortal.h embeds a DNSServer by value so it can answer
// the wildcard queries a captive-portal probe makes. The host run never starts
// or polls it, so start()/processNextRequest() are inert and stop() is the only
// thing that records anything — the class has to exist for the header to parse.
//
// This is a test scaffold only. It must never be on the include path for a real
// firmware build.

#include <cstdint>

#include <WiFi.h>  // IPAddress

class DNSServer {
 public:
  void start(uint16_t port, const char* domainName, const IPAddress& resolvedAddress) {
    (void)port;
    (void)domainName;
    (void)resolvedAddress;
    running_ = true;
  }
  void stop() { running_ = false; }
  void processNextRequest() {}
  bool running() const { return running_; }

 private:
  bool running_ = false;
};
