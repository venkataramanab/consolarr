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

Consolarr is pre-release and has had no store release yet, so only the
current `main` branch is supported. Fixes land on `main`.

## Security posture

- No telemetry SDKs in the foss app; any future telemetry is opt-in and lives
  only in the Play entry point. A test walks the resolved dependency graph of
  both apps for advertising, analytics and crash SDKs; the Play allowlist is
  empty.
- Android: `allowBackup="false"` with empty-by-exclusion data-extraction and
  backup rules; platform cleartext denied (per-server cleartext opt-in is
  enforced in Dart); R8 and obfuscation for release builds; deep links off;
  the root view ignores touches while another window covers it (tapjacking).
- Permissions (the merged manifest is checked in CI and may request nothing
  else):
  - `INTERNET`: to reach the servers you add.
  - `USE_BIOMETRIC`: the opt-in app lock (the system authenticator).
  - `USE_FINGERPRINT`: merged by `androidx.biometric` for the API 26-27
    fallback of that same prompt. Not used for anything else.
- Secrets live only in the Android Keystore-backed store. A Keystore error is
  never turned into "empty": the store is opened with `resetOnError: false`,
  reads fail closed (`SecretStoreUnavailable`), and the only way to clear is
  the user-confirmed "Reset secure storage" action. A pinned server whose pin
  disappeared is shown as a pin mismatch, never as a first-use prompt.
- Session cookies and ids (qBittorrent, Deluge, Transmission) are accepted
  only from a response whose **final hop** is the configured server's origin.
- CI: gitleaks, osv-scanner, Semgrep, licence checks, SHA-pinned actions and
  least-privilege workflow permissions.

## OWASP MASVS checklist

Status legend: `TODO` not started, `WIP` in progress, `DONE` implemented and
tested, `N/A` not applicable. Tracked against
[OWASP MASVS](https://mas.owasp.org/MASVS/). Paths are relative to the
repository root (`app` = `apps/consolarr/lib`).

| Control | Area | Status | Where |
| --- | --- | --- | --- |
| MASVS-STORAGE-1 | Secrets stored with OS-protected key storage | DONE | `app/src/storage/flutter_secure_secret_store.dart` (`resetOnError: false`, fail closed), `app/src/storage/pinned_markers.dart` (pin lost = mismatch), `app/src/storage/secure_storage_reset.dart` (user-confirmed reset) |
| MASVS-STORAGE-2 | No sensitive data in backups, logs or caches | DONE | `apps/*/android/app/src/main/res/xml/{backup_rules,data_extraction_rules}.xml`, `tools/ci/check_merged_manifest.py`, `packages/observability/lib/src/{redactor,diagnostics}.dart` (scrubbed log, closed route words), `app/src/platform/secure_screen.dart` |
| MASVS-CRYPTO-1 | Strong, current cryptography only | DONE | No custom cryptography; SHA-256 certificate fingerprints in `packages/security/lib/src/certificate.dart`, TLS by the platform |
| MASVS-CRYPTO-2 | Proper key management | DONE | The app creates no keys; wrapping keys are held by the Android Keystore through the secure-storage plugin |
| MASVS-AUTH-1 | Authentication to user servers handled securely | DONE | `app/features/servers/application/auth_headers.dart` (headers only, never URLs), final-hop session capture in `packages/torrent_clients/lib/src/client_support.dart` |
| MASVS-AUTH-2 | Local authentication (app lock) | DONE | `app/features/settings/application/lock_controller.dart` (monotonic cool-down, persisted failure counter), `.../presentation/app_lock_gate.dart` |
| MASVS-NETWORK-1 | TLS for all traffic, hostname verification always on | DONE | `packages/security/lib/src/http/secure_http_client_factory.dart`; per-server cleartext opt-in (`packages/core/lib/src/cleartext_policy.dart`); redirect policy |
| MASVS-NETWORK-2 | Trust-on-first-use pinning, mismatch blocking | DONE | Pin checked on every connection before any request bytes; explicit re-trust in `app/features/servers/presentation/certificate_flow.dart` |
| MASVS-PLATFORM-1 | Minimal exported components and permissions | DONE | `apps/*/android/app/src/main/AndroidManifest.xml`, `tools/ci/check_merged_manifest.py` (permissions, exports, backup resources), `MainActivity.kt` (`filterTouchesWhenObscured`), `apps/consolarr/test/android_hardening_test.dart` |
| MASVS-PLATFORM-2 | Safe handling of external input | DONE | External links are built from validated ids and fixed hosts (`packages/core/lib/src/external_hosts.dart`, `app/features/radarr/presentation/movie_detail_screen.dart`, `packages/arr_api/lib/src/sonarr/sonarr_series_detail.dart`); https only; deep links off |
| MASVS-CODE-1 | Dependencies scanned, builds reproducible-minded | DONE | osv-scanner, licence check and SHA-pinned actions in `.github/workflows/ci.yml` |
| MASVS-CODE-2 | Input validation, no unsafe parsing | DONE | `ServerProfile.parse`, tolerant row parsers (`packages/core/lib/src/parsed_rows.dart`), response size caps and deadlines in the secure client |
| MASVS-RESILIENCE-1 | Obfuscation / release hardening | WIP | R8 + `--obfuscate` enabled; verified per release |
| MASVS-PRIVACY-1 | Data minimisation, no tracking by default | DONE | Consent gate and typed crash payload (`packages/observability/lib/src/{consent_gating,crash_payload}.dart`), closed-enum event catalog with feature prefixes and bucketed counts, no SDKs (`apps/consolarr/test/no_telemetry_test.dart`) |
| MASVS-PRIVACY-2 | Transparent third-party contact | DONE | Every host opened on a tap is listed in the About statement and the README; a test fails when one is missing (`apps/consolarr/test/about/external_hosts_test.dart`) |
