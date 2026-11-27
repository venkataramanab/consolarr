# Architecture

Consolarr is a melos/pub-workspace monorepo. The root `pubspec.yaml` lists the
workspace members; `flutter pub get` at the root resolves everything into one
`pubspec.lock`.

```
apps/consolarr  ────────────┐          (foss app + shared app library)
apps/consolarr_play ──────► consolarr   (Play entry point, only place for telemetry SDKs)

            ┌─────────── features (apps/consolarr/lib/features/*) ───────────┐
            ▼                ▼                 ▼               ▼              ▼
     design_system         l10n         observability      arr_api      torrent_clients
                                                              │               │
                                                              ▼               ▼
                                                            core ◄──────── security
```

## Packages

| Package | Kind | Depends on | Purpose |
| --- | --- | --- | --- |
| `core` | pure Dart | - | `ServerProfile`, `Result`/`AppError` + `ErrorCategory`, `CleartextPolicy`. |
| `security` | pure Dart | `core`, `dio` | `SecretStore`, `PinStore` (+ `PinKey`, `UserPinConfirmation`, `decidePin`), `SecureHttpClientFactory` contracts. The only package allowed to touch TLS trust. |
| `arr_api` | pure Dart | `core` | `SonarrApi` / `RadarrApi` interfaces. |
| `torrent_clients` | pure Dart | `core` | `TorrentClient` interface. |
| `observability` | pure Dart | - | `CrashReporter`, `Analytics`, `ConsentStore` + no-ops, `Redactor`, `AppLogger`. No SDKs. |
| `design_system` | Flutter | - | Tokens, theme, bundled Inter font. |
| `l10n` | Flutter | `material_ui` | Generated `AppLocalizations`, merged from feature ARBs. |
| `test_harness` | Flutter, dev-only | `design_system`, `l10n`, `dio` | Matrix pumping, accessibility, goldens, fault injection, first-frame guard. |
| `apps/consolarr` | Flutter app | UI packages + `observability` | App shell, router, features. Library + `main.dart`. |
| `apps/consolarr_play` | Flutter app | `consolarr`, `observability` | Play entry point. |

## Dependency rules

1. **Features depend on packages, never the other way round.** Packages must
   not import from `apps/`.
2. **`core` and `security` have no UI.** They must not depend on Flutter,
   `design_system`, `l10n` or `material_ui`. Keep them pure Dart so they can be
   unit-tested with `dart test` semantics and reused.
3. **API packages (`arr_api`, `torrent_clients`) depend on `core` only** (plus
   `security` for HTTP when implemented), never on UI packages.
4. **`observability` has no third-party SDKs.** Telemetry SDKs may only be
   added to `apps/consolarr_play`, wired in by overriding Riverpod providers
   (`crashReporterProvider`, `analyticsProvider`, `consentStoreProvider`).
   A test walks the resolved dependency graph (`dart pub deps --json`) and fails
   if the foss app gains a telemetry dependency, direct or transitive.
5. **`test_harness` is a dev dependency only**; production code never imports it.
6. **All HTTP goes through `SecureHttpClientFactory`.** TLS trust APIs
   (`badCertificateCallback`, `onBadCertificate`, `HttpOverrides`,
   `setTrustedCertificates`, `withTrustedRoots: false`) are only allowed in
   `packages/security/lib/src/http/secure_http_client_factory.dart` (lint +
   Semgrep; the test harness's access guard may name `HttpOverrides` to observe
   client creation). The rule also covers generated `*.g.dart` files, and CI
   fails on any `// ignore: consolarr_...` / `nosemgrep` suppression that is
   not in `tools/ci/suppression_allowlist.txt`. `.github/CODEOWNERS` requires
   the owner's review for `packages/security/**`, `tools/**` and `.github/**`.
7. **No hardcoded user-facing text.** Strings live in per-feature ARB files.

## Application shell

- `MaterialApp.router` (`go_router`) inside a Riverpod `ProviderScope`.
- Localizations and theme come from `l10n` and `design_system`; dark is the
  default.
- Nothing runs before the first frame: `main()` only calls `runApp`; routers
  and providers are created lazily.

## Cleartext traffic

Dart's own sockets (`dart:io`) do not consult Android's network security
configuration, so the manifest flag (`usesCleartextTraffic="false"`) only covers
platform HTTP stacks. Per-server cleartext opt-in is therefore enforced in Dart
by `CleartextPolicy` (package `core`), which every client factory must call.

## Certificate pinning contract (TOFU)

- A pin is addressed by `PinKey` (server-profile id, normalised host, explicit
  port) and holds a SHA-256 `CertificateFingerprint`.
- `decidePin` is evaluated for **every** TLS connection, not only when the
  platform rejects the chain. A pinned server presenting a different
  certificate is blocked even if that certificate chains to a system CA.
- With no pin and an untrusted chain the verdict is `unpinnedUntrusted` and the
  bad-certificate callback returns `false`; only the confirmation UI may then
  create a pin.
- `PinStore.write`/`clear` require a `UserPinConfirmation` bound to exactly the
  key and fingerprint the user saw. A Semgrep rule rejects constructing it
  outside the confirmation UI.
- `ServerProfile.parse` rejects credentials and query strings in the address.

## Localization pipeline

1. Hand-written ARB files per feature:
   `apps/consolarr/lib/features/<feature>/l10n/app_{en,ar}.arb`.
2. `dart run melos run l10n` merges them (failing on duplicate keys) into
   `packages/l10n/lib/arb/`, generates `app_en_XA.arb` (accented, ~40% longer;
   never hand-edited) and runs `flutter gen-l10n`.
3. `packages/l10n/test/l10n_keys_test.dart` fails on missing/extra keys, missing
   `@description`, unused keys (real `l10n.<key>` / `AppLocalizations.of(..).<key>`
   accessors only; comments and string contents are ignored) or stale generated
   files.
4. Use `appLocalizationsDelegates` (not the generated
   `AppLocalizations.localizationsDelegates`) with `MaterialApp`, because the
   Material library now lives in the `material_ui` package.

## Quality gates

See `.github/workflows/ci.yml`. In short: format, analyze (VGA lints plus
`tools/consolarr_lints`), SPDX, suppression guard, l10n drift (including
untracked files), tests with coverage and goldens, gitleaks (pinned release
binary, checksum-verified, with a planted-token canary), osv-scanner (both
lockfiles), Semgrep (hash-locked install), licence check, Gradle wrapper
validation, repo guard (clean-room terms from a secret, never printed),
debug builds of both apps with assertions on the **merged** Android manifest
(only INTERNET requested, only the launcher activity exported) and an arm64
release APK size gate (20 MiB). Release builds without `key.properties` are
refused unless debug signing is explicitly allowed (CI does). A nightly workflow runs an emulator smoke
test on API 34.
