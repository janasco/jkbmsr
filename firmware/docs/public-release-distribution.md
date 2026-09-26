# Public Release Distribution

JKBMSR firmware source remains private.

Public distributable artifacts belong in the public `jkbmsr-releases` repository.

## Public Release Repository

- Repository: `jkbmsr-releases`
- Visibility: public
- Scope: release artifacts only

## Public Artifacts

Each published firmware version should expose:

- `firmware.bin`
- `firmware.sha256`
- signed OTA metadata
- release manifest
- release notes
- public OTA verification key

## Rules

- Do not publish firmware source code in `jkbmsr-releases`
- Do not publish private signing keys
- Do not publish Cloudflare or GitHub secrets
- Keep release metadata aligned with the production OTA release

## Workflow Note

The firmware OTA release workflow can optionally mirror published release artifacts into `jkbmsr-releases` when a cross-repository push token is configured.

When cross-repository publishing is enabled, the workflow should validate:

- the signed OTA bundle before any publish step
- the generated `firmware/latest.json`
- the generated `firmware/releases.json`
- the generated per-version `release.json`
- the public checksum file inside the mirrored version directory
