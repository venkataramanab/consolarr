# Security policy

## Reporting a vulnerability

Please report vulnerabilities **privately** using GitHub Security Advisories:
open the repository's **Security** tab and choose **Report a vulnerability**
(a private advisory). Do not open a public issue, pull request or discussion
for a suspected vulnerability, and do not include real server addresses,
credentials or personal data in your report.

You can expect an acknowledgement within a few days. We will keep you
informed, credit you if you wish, and publish an advisory when a fix is
released.

## Supported versions

Only the latest release is supported while the project is pre-1.0.

## Security posture (foundation)

- No telemetry SDKs in the foss app; any future telemetry is opt-in and lives
  only in the Play entry point.
- Android: `allowBackup="false"`, empty data-extraction rules, a single
  `INTERNET` permission, platform cleartext denied (per-server cleartext
  opt-in is enforced in Dart), R8 and obfuscation for release builds.
- CI: gitleaks, osv-scanner, Semgrep, licence checks, SHA-pinned actions and
  least-privilege workflow permissions.

## OWASP MASVS checklist (skeleton)

Status legend: `TODO` not started, `WIP` in progress, `DONE` implemented and
tested, `N/A` not applicable. MVP controls are listed as TODO and are tracked
against [OWASP MASVS](https://mas.owasp.org/MASVS/).

| Control | Area | Status | Notes |
| --- | --- | --- | --- |
| MASVS-STORAGE-1 | Secrets stored with OS-protected key storage | TODO | `SecretStore` interface exists; implementation pending |
| MASVS-STORAGE-2 | No sensitive data in backups, logs or caches | TODO | Backups disabled in manifest; backup-content test pending; `Redactor` in place |
| MASVS-CRYPTO-1 | Strong, current cryptography only | TODO | Applies to pinning fingerprints and any export format |
| MASVS-CRYPTO-2 | Proper key management | TODO | |
| MASVS-AUTH-1 | Authentication to user servers handled securely | TODO | Credentials in separate fields, never in URLs |
| MASVS-AUTH-2 | Local authentication (app lock) | TODO | Later |
| MASVS-NETWORK-1 | TLS for all traffic, hostname verification always on | TODO | `SecureHttpClientFactory` contract defined |
| MASVS-NETWORK-2 | Trust-on-first-use pinning, mismatch blocking | TODO | Planned for W3 |
| MASVS-PLATFORM-1 | Minimal exported components and permissions | TODO | Manifest hardened; review per release |
| MASVS-PLATFORM-2 | Safe handling of external input | TODO | |
| MASVS-CODE-1 | Dependencies scanned, builds reproducible-minded | TODO | osv-scanner and licence check in CI |
| MASVS-CODE-2 | Input validation, no unsafe parsing | TODO | |
| MASVS-RESILIENCE-1 | Obfuscation / release hardening | TODO | R8 + `--obfuscate` enabled; verify per release |
| MASVS-PRIVACY-1 | Data minimisation, no tracking by default | TODO | Telemetry off by default, opt-in only |
| MASVS-PRIVACY-2 | Transparent third-party contact | TODO | |
