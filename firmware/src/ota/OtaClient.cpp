#include "OtaClient.h"

#include <ArduinoJson.h>
#include <Update.h>
#include <esp_arduino_version.h>
#include <mbedtls/base64.h>
#include <mbedtls/pk.h>
#include <mbedtls/sha256.h>

#include "debug/DebugLog.h"
#include "HardwareProfile.h"
#include "net/PlatformNetwork.h"
#include "net/SecureClient.h"
#include "ota/VersionCompare.h"
#include "OtaSigningKey.h"

namespace jkbmsr {

namespace {
// HTTPClient::getStreamPtr() returns WiFiClient* on the older core every
// target but esp32-c6-4mb builds against, and NetworkClient* (the newer
// WiFiClient/EthernetClient-unifying base) on the core esp32-c6-4mb uses
// via the pioarduino platform fork — see platformio.ini and SecureClient.cpp
// for the same core-version split.
#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
using PlatformStreamClient = NetworkClient;
#else
using PlatformStreamClient = WiFiClient;
#endif
}  // namespace

OtaClient::OtaClient(String apiBaseUrl) : apiBaseUrl_(apiBaseUrl) {}

namespace {

String bytesToHex(const uint8_t* bytes, size_t length) {
  constexpr char kHex[] = "0123456789abcdef";
  String output;
  output.reserve(length * 2);
  for (size_t index = 0; index < length; ++index) {
    output += kHex[(bytes[index] >> 4) & 0x0f];
    output += kHex[bytes[index] & 0x0f];
  }
  return output;
}

bool readUpdateMetadata(
    const String& apiBaseUrl,
    const String& token,
    bool& updateAvailable,
    String& version,
    String& targetHardware,
    String& releasedAt,
    String& downloadUrl,
    String& sha256,
    String& signature,
    String& signingKeyId,
    String& signatureAlgorithm,
    String& failureReason) {
  GatewaySecureClient client;
  configureSecureClient(client);

  HTTPClient http;
  if (!http.begin(client, apiBaseUrl + "/v1/ota/latest")) {
    logError("OTA metadata request could not start");
    failureReason = "metadata-request-start-failed";
    return false;
  }

  http.addHeader("Authorization", "Bearer " + token);
  const int status = http.GET();
  const String response = http.getString();
  http.end();

  if (status != HTTP_CODE_OK) {
    logWarn("OTA metadata request failed with status " + String(status));
    failureReason = "metadata-request-http-" + String(status);
    return false;
  }

  JsonDocument document;
  const DeserializationError error = deserializeJson(document, response);
  if (error) {
    logError("OTA metadata JSON parse failed");
    failureReason = "metadata-json-parse-failed";
    return false;
  }

  updateAvailable = document["updateAvailable"] | false;
  version = document["version"] | "";
  targetHardware = document["targetHardware"] | "";
  releasedAt = document["releasedAt"] | "";
  downloadUrl = document["downloadUrl"] | "";
  sha256 = document["sha256"] | "";
  signature = document["signature"] | "";
  signingKeyId = document["signingKeyId"] | "";
  signatureAlgorithm = document["signatureAlgorithm"] | "";
  failureReason = "";
  return true;
}

String buildMetadataPayload(
    const String& version,
    const String& targetHardware,
    const String& releasedAt,
    const String& sha256) {
  String payload;
  payload.reserve(version.length() + targetHardware.length() + releasedAt.length() + sha256.length() + 4);
  payload += version;
  payload += '\n';
  payload += targetHardware;
  payload += '\n';
  payload += releasedAt;
  payload += '\n';
  payload += sha256;
  return payload;
}

bool verifyMetadataSignature(
    const String& version,
    const String& targetHardware,
    const String& releasedAt,
    const String& sha256,
    const String& signature,
    const String& signingKeyId,
    const String& signatureAlgorithm,
    String& failureReason) {
  if (version.length() == 0 ||
      targetHardware.length() == 0 ||
      releasedAt.length() == 0 ||
      sha256.length() != 64 ||
      signature.length() == 0 ||
      signingKeyId.length() == 0 ||
      signatureAlgorithm.length() == 0) {
    failureReason = "metadata-signature-incomplete";
    return false;
  }

  if (targetHardware != kTargetHardware) {
    failureReason = "metadata-target-unsupported";
    return false;
  }

  if (signingKeyId != kOtaSigningKeyId) {
    failureReason = "metadata-signing-key-mismatch";
    return false;
  }

  if (signatureAlgorithm != kOtaSignatureAlgorithm) {
    failureReason = "metadata-signature-algorithm-mismatch";
    return false;
  }

  const String payload = buildMetadataPayload(version, targetHardware, releasedAt, sha256);
  uint8_t hash[32];
  mbedtls_sha256(
      reinterpret_cast<const uint8_t*>(payload.c_str()),
      payload.length(),
      hash,
      0);

  size_t signatureLength = 0;
  unsigned char signatureBytes[128] = {};
  const int decodeResult = mbedtls_base64_decode(
      signatureBytes,
      sizeof(signatureBytes),
      &signatureLength,
      reinterpret_cast<const unsigned char*>(signature.c_str()),
      signature.length());
  if (decodeResult != 0) {
    failureReason = "metadata-signature-base64-invalid";
    return false;
  }

  mbedtls_pk_context publicKey;
  mbedtls_pk_init(&publicKey);
  const int parseResult = mbedtls_pk_parse_public_key(
      &publicKey,
      reinterpret_cast<const unsigned char*>(kOtaPublicKeyPem),
      strlen(kOtaPublicKeyPem) + 1);
  if (parseResult != 0) {
    mbedtls_pk_free(&publicKey);
    failureReason = "metadata-public-key-parse-failed";
    return false;
  }

  const int verifyResult = mbedtls_pk_verify(
      &publicKey,
      MBEDTLS_MD_SHA256,
      hash,
      sizeof(hash),
      signatureBytes,
      signatureLength);
  mbedtls_pk_free(&publicKey);
  if (verifyResult != 0) {
    failureReason = "metadata-signature-invalid";
    return false;
  }

  failureReason = "";
  return true;
}

bool downloadAndApplyUpdate(
    const String& token,
    const String& downloadUrl,
    const String& expectedSha256,
    String& failureReason) {
  if (downloadUrl.length() == 0 || expectedSha256.length() != 64) {
    logError("OTA update metadata is incomplete");
    failureReason = "metadata-incomplete";
    return false;
  }

  GatewaySecureClient client;
  configureSecureClient(client);

  HTTPClient http;
  if (!http.begin(client, downloadUrl)) {
    logError("OTA firmware download request could not start");
    failureReason = "download-request-start-failed";
    return false;
  }

  http.addHeader("Authorization", "Bearer " + token);
  const int status = http.GET();
  if (status != HTTP_CODE_OK) {
    logWarn("OTA firmware download failed with status " + String(status));
    http.end();
    failureReason = "download-http-" + String(status);
    return false;
  }

  const int contentLength = http.getSize();
  if (contentLength <= 0) {
    logError("OTA firmware size is invalid");
    http.end();
    failureReason = "download-size-invalid";
    return false;
  }

  if (!Update.begin(contentLength)) {
    logError("OTA update partition is not ready");
    http.end();
    failureReason = "update-partition-unavailable";
    return false;
  }

  mbedtls_sha256_context shaContext;
  mbedtls_sha256_init(&shaContext);
  // The "_ret" suffix (mbedtls_sha256_starts_ret/update_ret/finish_ret) was
  // mbedtls 2.7+'s transitional name for these functions; mbedtls 3.x
  // (env:esp32-c6-4mb's newer core pulls in a newer IDF/mbedtls) dropped the
  // suffix and reused the plain name for the same signature. The plain name
  // (mbedtls_sha256_starts/update/finish) exists in both versions — only
  // the return value differs (void vs int) — and every call here already
  // discards the return value, so the plain name works unconditionally.
  mbedtls_sha256_starts(&shaContext, 0);

  PlatformStreamClient* stream = http.getStreamPtr();
  uint8_t buffer[1024];
  int remaining = contentLength;
  size_t written = 0;

  while (remaining > 0 && http.connected()) {
    const size_t available = stream->available();
    if (available == 0) {
      delay(1);
      continue;
    }

    const size_t toRead = min(available, sizeof(buffer));
    const int bytesRead = stream->readBytes(buffer, toRead);
    if (bytesRead <= 0) {
      continue;
    }

    mbedtls_sha256_update(&shaContext, buffer, bytesRead);
    const size_t bytesWritten = Update.write(buffer, bytesRead);
    if (bytesWritten != static_cast<size_t>(bytesRead)) {
      logError("OTA firmware write failed");
      Update.abort();
      mbedtls_sha256_free(&shaContext);
      http.end();
      failureReason = "update-write-failed";
      return false;
    }

    written += bytesWritten;
    remaining -= bytesRead;
  }

  uint8_t digest[32];
  mbedtls_sha256_finish(&shaContext, digest);
  mbedtls_sha256_free(&shaContext);
  http.end();

  if (written != static_cast<size_t>(contentLength)) {
    logError("OTA firmware download ended before expected size");
    Update.abort();
    failureReason = "download-truncated";
    return false;
  }

  const String actualSha256 = bytesToHex(digest, sizeof(digest));
  if (!actualSha256.equalsIgnoreCase(expectedSha256)) {
    logError("OTA firmware SHA-256 verification failed");
    Update.abort();
    failureReason = "sha256-mismatch";
    return false;
  }

  if (!Update.end(true)) {
    logError("OTA update finalization failed");
    failureReason = "update-finalization-failed";
    return false;
  }

  failureReason = "";
  logInfo("OTA update applied; restarting");
  ESP.restart();
  return true;
}

}  // namespace

const OtaStatus& OtaClient::status() const {
  return status_;
}

void OtaClient::setStatus(
    uint32_t lastCheckAtMs,
    bool lastCheckSucceeded,
    bool updateAvailable,
    bool updateApplied,
    const String& offeredVersion,
    const String& lastResult) {
  status_.lastCheckAtMs = lastCheckAtMs;
  status_.lastCheckSucceeded = lastCheckSucceeded;
  status_.updateAvailable = updateAvailable;
  status_.updateApplied = updateApplied;
  status_.offeredVersion = offeredVersion;
  status_.lastResult = lastResult;
}

bool OtaClient::checkForUpdate(const String& token, const String& currentVersion, const String& versionFloor) {
  const uint32_t checkAtMs = millis();
  if (token.length() == 0 || currentVersion.length() == 0) {
    logWarn("OTA check skipped because auth or version is missing");
    setStatus(checkAtMs, false, false, false, "", "skipped-missing-auth-or-version");
    return false;
  }

  bool updateAvailable = false;
  String version;
  String targetHardware;
  String releasedAt;
  String downloadUrl;
  String sha256;
  String signature;
  String signingKeyId;
  String signatureAlgorithm;
  String failureReason;
  if (!readUpdateMetadata(
          apiBaseUrl_,
          token,
          updateAvailable,
          version,
          targetHardware,
          releasedAt,
          downloadUrl,
          sha256,
          signature,
          signingKeyId,
          signatureAlgorithm,
          failureReason)) {
    setStatus(checkAtMs, false, false, false, version, failureReason);
    return false;
  }

  if (!updateAvailable) {
    logInfo("No OTA update available");
    setStatus(checkAtMs, true, false, false, "", "no-update-available");
    return false;
  }

  if (version.length() == 0 || version == currentVersion) {
    logInfo("OTA update skipped because firmware is current");
    setStatus(checkAtMs, true, false, false, version, "already-current");
    return false;
  }

  if (!verifyMetadataSignature(
          version,
          targetHardware,
          releasedAt,
          sha256,
          signature,
          signingKeyId,
          signatureAlgorithm,
          failureReason)) {
    logError("OTA metadata signature verification failed");
    setStatus(checkAtMs, false, true, false, version, failureReason);
    return false;
  }

  // Anti-rollback: even a correctly-signed release is refused if it is not
  // strictly newer than the highest version this device has ever run. This
  // blocks replay/forced-downgrade to an older (possibly vulnerable) build.
  // The floor is empty only on a device that has never recorded one; in that
  // case fall back to the running version so we still never go backwards.
  const String floor = versionFloor.length() > 0 ? versionFloor : currentVersion;
  if (!isStrictlyNewer(version, floor)) {
    logWarn("OTA update blocked (anti-rollback): offered " + version + " is not newer than floor " + floor);
    setStatus(checkAtMs, false, true, false, version, "rollback-blocked");
    return false;
  }

  logInfo("OTA update available: " + version);
  if (!downloadAndApplyUpdate(token, downloadUrl, sha256, failureReason)) {
    setStatus(checkAtMs, false, true, false, version, failureReason);
    return false;
  }

  setStatus(checkAtMs, true, true, true, version, "update-applied");
  return true;
}

}  // namespace jkbmsr
