#pragma once

namespace jkbmsr {

constexpr const char* kOtaSigningKeyId = "jkbmsr-ota-p256-20261009";
constexpr const char* kOtaSignatureAlgorithm = "ecdsa-p256-sha256";
constexpr const char* kOtaPublicKeyPem = R"(-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjSdYoRFDH0+MKSuSQHb5a2GDx2ro
fJRoHq9akpUKR26JsorOWAFc8g0GQVkaMWtSEKRw4tkkMaJn1eXPMJwCuA==
-----END PUBLIC KEY-----
)";

}  // namespace jkbmsr
