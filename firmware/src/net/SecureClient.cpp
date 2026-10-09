#include "SecureClient.h"

#include "AppConfig.h"

#if defined(ARDUINO_ARCH_ESP8266)
#include <BearSSLHelpers.h>
#else
#include <esp_arduino_version.h>
#endif

namespace jkbmsr {

#if defined(ARDUINO_ARCH_ESP8266)

// ESP8266's WiFiClientSecure is BearSSL-based and has no setCACertBundle()
// equivalent (that's an arduino-esp32/esp-idf-only API) — nor could it fit
// the full embedded Mozilla bundle used on ESP32 in this chip's much
// smaller RAM budget. Two roots are embedded instead of one specifically
// because this target has no OTA (see platformio.ini's env:esp8266-
// nodemcu): if the single embedded root ever stopped matching the chain
// Cloudflare serves for api.jkbmsr.com, every deployed device would lose
// cloud connectivity permanently with no remote recovery, only a physical
// USB reflash. The two anchors here are:
//  1. GlobalSign ECC Root CA - R4 — what api.jkbmsr.com's chain actually
//     verifies against today: Google Trust Services' "WE1" intermediate is
//     cross-signed by this GlobalSign root (confirmed via
//     `openssl verify -partial_chain` against the live chain).
//  2. ISRG Root X1 (Let's Encrypt) — a second, widely-used anchor as a
//     hedge against a future CA change, not because it's currently in use.
// See docs/tls-trust-and-cert-rotation.md and docs/esp8266-nodemcu-
// support.md for rotation/verification notes. Real cert validation, not a
// setInsecure() fallback — this header's own history is exactly why:
// setInsecure() previously accepted any certificate and left every cloud
// connection open to a trivial man-in-the-middle.
static const char kGlobalSignEccRootR4[] PROGMEM = R"CERT(
-----BEGIN CERTIFICATE-----
MIIB3DCCAYOgAwIBAgINAgPlfvU/k/2lCSGypjAKBggqhkjOPQQDAjBQMSQwIgYD
VQQLExtHbG9iYWxTaWduIEVDQyBSb290IENBIC0gUjQxEzARBgNVBAoTCkdsb2Jh
bFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTIxMTEzMDAwMDAwWhcNMzgw
MTE5MDMxNDA3WjBQMSQwIgYDVQQLExtHbG9iYWxTaWduIEVDQyBSb290IENBIC0g
UjQxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wWTAT
BgcqhkjOPQIBBggqhkjOPQMBBwNCAAS4xnnTj2wlDp8uORkcA6SumuU5BwkWymOx
uYb4ilfBV85C+nOh92VC/x7BALJucw7/xyHlGKSq2XE/qNS5zowdo0IwQDAOBgNV
HQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUVLB7rUW44kB/
+wpu+74zyTyjhNUwCgYIKoZIzj0EAwIDRwAwRAIgIk90crlgr/HmnKAWBVBfw147
bmF0774BxL4YSFlhgjICICadVGNA3jdgUM/I2O2dgq43mLyjj0xMqTQrbO/7lZsm
-----END CERTIFICATE-----
)CERT";

static const char kIsrgRootX1[] PROGMEM = R"CERT(
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)CERT";

void configureSecureClient(GatewaySecureClient& client) {
  static BearSSL::X509List trustAnchors(kGlobalSignEccRootR4);
  trustAnchors.append(kIsrgRootX1);
  client.setTrustAnchors(&trustAnchors);
  // BearSSL::WiFiClientSecure has no setHandshakeTimeout() (that's an
  // arduino-esp32-only API) — Stream::setTimeout() (milliseconds) is this
  // core's closest equivalent, bounding blocking reads generally rather
  // than the handshake specifically, but serves the same practical purpose.
  client.setTimeout(kTlsHandshakeTimeoutSeconds * 1000);
  // BearSSL's default record buffers (16KB in, 16KB out) don't fit ESP8266's
  // ~50KB total heap alongside WiFi/HTTP/JSON buffers — shrink to the
  // minimum BearSSL allows (still enough for this API's small JSON payloads
  // and single-cert-chain handshakes) rather than fragmenting/failing under
  // memory pressure.
  client.setBufferSizes(512, 512);
}

#else

// Embedded at link time from data/cert/x509_crt_bundle.bin.
// - env:dev (pure Arduino): PlatformIO board_build.embed_files derives the
//   symbol from the full path → _binary_data_cert_x509_crt_bundle_bin_start
// - env:idf (Arduino-as-IDF): target_add_binary_data in src/CMakeLists.txt
//   derives the symbol from the filename → _binary_x509_crt_bundle_bin_start
#if defined(JKBMSR_ARDUINO_AS_IDF)
// ESP-IDF mbedtls certificate bundle (CONFIG_MBEDTLS_CERTIFICATE_BUNDLE).
extern const uint8_t rootca_crt_bundle_start[] asm("_binary_x509_crt_bundle_start");
extern const uint8_t rootca_crt_bundle_end[] asm("_binary_x509_crt_bundle_end");
#else
// PlatformIO board_build.embed_files → path-derived symbol.
extern const uint8_t rootca_crt_bundle_start[] asm("_binary_data_cert_x509_crt_bundle_bin_start");
extern const uint8_t rootca_crt_bundle_end[] asm("_binary_data_cert_x509_crt_bundle_bin_end");
#endif

void configureSecureClient(GatewaySecureClient& client) {
  // Arduino-ESP32 core 3.x (env:esp32-c6-4mb only, via the pioarduino
  // platform fork — see platformio.ini) changed setCACertBundle() to take an
  // explicit size instead of relying on a null/sentinel-terminated bundle.
  // Every other target still builds against core ~2.0.17 (PlatformIO's
  // official espressif32 platform pins it as registry version "3.20017",
  // its own encoding, not an upstream Arduino-ESP32 version) with the
  // single-argument overload.
#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
  client.setCACertBundle(rootca_crt_bundle_start, static_cast<size_t>(rootca_crt_bundle_end - rootca_crt_bundle_start));
#else
  client.setCACertBundle(rootca_crt_bundle_start);
#endif
  client.setHandshakeTimeout(kTlsHandshakeTimeoutSeconds);
  // Bound the *body* read as well as the handshake. setHandshakeTimeout only
  // covers the TLS negotiation; once the server has completed it, a stalled or
  // truncated response would otherwise block loop() indefinitely, because every
  // HTTP call site here is synchronous. The loop-task watchdog then resets the
  // device, so the symptom is a periodic boot loop rather than a permanent
  // hang — but the gateway still goes dark every time. This also gives the OTA
  // download loop its idle timeout, which README.md had tracked as outstanding.
  // WiFiClientSecure::setTimeout() takes SECONDS on arduino-esp32 — internally
  // `_timeout = seconds * 1000`. This differs from Stream::setTimeout() (ms) on
  // the ESP8266 path above, and passing `* 1000` here made the intended 30s read
  // bound 30 000 000 ms (~8 h), i.e. no bound at all.
  client.setTimeout(kTlsReadTimeoutSeconds);
  // No arduino-esp32 core exposes WiFiClientSecure::setReadTimeout() — verified
  // against both 2.0.17 (official espressif32, pinned above) and 3.3.11 (the C6
  // pioarduino fork). The two calls above (setHandshakeTimeout for the
  // negotiation, setTimeout for blocking reads) are the whole available
  // surface; the previous setReadTimeout() call could not compile on either.
}

#endif

}  // namespace jkbmsr
