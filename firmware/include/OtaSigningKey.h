#pragma once

namespace jkbmsr {

constexpr const char* kOtaSigningKeyId = "jkbmsr-ota-p256-20260705";
constexpr const char* kOtaSignatureAlgorithm = "ecdsa-p256-sha256";
constexpr const char* kOtaPublicKeyPem = R"(-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1byxMq3y36fgYhQiF2v0QT/JCo3A
59km2WVyAxVYpb1aZOI56sLcWUnmbE3LV3aFch+xMSP/yop4fzsnLC5G0A==
-----END PUBLIC KEY-----
)";

}  // namespace jkbmsr
