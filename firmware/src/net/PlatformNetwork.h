#pragma once

#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
using GatewaySecureClient = BearSSL::WiFiClientSecure;
#else
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
using GatewaySecureClient = WiFiClientSecure;
#endif
