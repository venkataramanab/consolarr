# Consolarr

[![CI](https://github.com/venkataramanab/consolarr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/venkataramanab/consolarr/actions/workflows/ci.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
[![Min Android: API 26](https://img.shields.io/badge/Android-API%2026%2B-3ddc84)](#building-from-source)

Consolarr is a free, open-source (GPL-3.0-or-later) Flutter app for Android
phones (minimum API 26) that remotely controls your **self-hosted** media
services: Sonarr, Radarr, qBittorrent, Transmission and Deluge.

> **Status: pre-release, under active development.** There has been no store
> release yet, and features may change or be incomplete. Only `main` is
> supported (see [SECURITY.md](SECURITY.md)).

Consolarr is an independent project. It is **not affiliated with, endorsed by
or sponsored by** Sonarr, Radarr, the Servarr project, the torrent clients it
can talk to, or any other client app or service. All product names belong to
their owners.

## Features

Available on `main` today:

- **Server management:** add, edit and test servers; credentials stay in
  separate fields; trust-on-first-use (TOFU) certificate pinning with explicit
  re-trust; plain HTTP only after a per-server cleartext opt-in.
- **Sonarr:** library, series detail, calendar, queue, search, add series and
  wanted.
- **qBittorrent:** torrent list.
- **Settings:** app lock, consent, diagnostics, theme, language,
  accessibility and about.
- **Design system:** shared tokens, theme and components.

In progress: Radarr, Transmission and Deluge support, and torrent actions
(pause, resume, delete, add).

## Privacy and security

- API keys and passwords are stored only in the Android Keystore.
- TLS is always verified, with trust-on-first-use certificate pinning; a
  changed certificate blocks the connection until you re-trust it.
- No ads.
- The F-Droid/foss build contains **no telemetry SDKs at all**.
- The Play build currently contains no telemetry SDKs either. Any telemetry
  added there in future will be opt-in, off by default, and will never send
  hostnames, URLs, API keys or media titles.
- Diagnostics are redacted and shown for review before you share anything.

See [SECURITY.md](SECURITY.md) for the security posture and how to report
vulnerabilities privately.

## Accessibility and languages

TalkBack support, reduced motion and high contrast; layouts are tested at
200% text scale.
Available in English and Arabic (right-to-left); there are no hardcoded
user-facing strings.

## Repository layout

| Path | What it is |
| --- | --- |
| `apps/consolarr` | The foss app. All UI lives here as a library (`package:consolarr/consolarr.dart`) plus the `main.dart` entry point. No telemetry dependencies. |
| `apps/consolarr_play` | Play Store entry point. Reuses `apps/consolarr` as a library. The only place telemetry SDKs may ever be added (none today). |
| `packages/core` | `ServerProfile`, `Result`/`AppError`, cleartext policy. Pure Dart, no UI. |
| `packages/security` | `SecretStore`, `PinStore`, `SecureHttpClientFactory` interfaces. No UI. |
| `packages/arr_api` | `SonarrApi` / `RadarrApi` interfaces. |
| `packages/torrent_clients` | `TorrentClient` interface. |
| `packages/design_system` | Design tokens (colour roles, type scale, spacing, radii, blur, motion), theme, bundled Inter font. |
| `packages/observability` | `CrashReporter`, `Analytics`, `ConsentStore` interfaces + no-ops, `Redactor`, `AppLogger`. No SDKs. |
| `packages/l10n` | Generated localizations merged from per-feature ARB files. |
| `packages/test_harness` | Test helpers (dev dependency only). |
| `tools/consolarr_lints` | Analyzer plugin with the project lint rules. |
| `tools/ci`, `tools/semgrep` | CI helper scripts and Semgrep rules. |
| `tools/integration` | Scripts for integration tests against local services. |

See [docs/architecture.md](docs/architecture.md) for the dependency rules.

## Building from source

Prerequisites: the Flutter version pinned in [`.fvmrc`](.fvmrc)
(currently **3.50.1**, stable; use [FVM](https://fvm.app) or install that
version), the Android SDK and JDK 17+.

From a fresh checkout:

```sh
dart packages/l10n/tool/build_l10n.dart --arb-only  # merge per-feature ARB files
flutter pub get                                     # resolves the whole workspace
dart run melos run codegen                          # event catalog, l10n, drift
flutter run                                         # from apps/consolarr
```

Debug builds need **no secrets**, so a fork can build and run without any
configuration, and telemetry is off. Release builds require signing: a release
build fails without a git-ignored `key.properties` so a debug-signed APK can
never be shipped by accident. For a local, non-distributable release build (CI
does this too) opt in explicitly:

```sh
ORG_GRADLE_PROJECT_consolarr.allowDebugSigning=true dart run melos run build:release
```

Release builds use `--obfuscate --split-debug-info` (keep the generated
`build/debug-info` symbols to de-obfuscate stack traces).

Useful tasks:

- `dart run melos run analyze` and `dart run melos run test` run analysis
  (including the custom lints) and the unit, widget and golden tests.
- `dart run melos run build:debug` builds debug APKs for both apps.
- `dart run melos run codegen` generates everything that is git-ignored; run
  it after `flutter pub get` and after merging a branch that changed an ARB
  file, an event YAML or a drift table. Edit the per-feature ARB files under
  `apps/consolarr/lib/features/<feature>/l10n/` (shared strings:
  `apps/consolarr/lib/shared/l10n/`), never the generated output.
- `dart run melos run goldens:update` regenerates golden images.
- Optional: install [lefthook](https://github.com/evilmartians/lefthook) and
  [gitleaks](https://github.com/gitleaks/gitleaks), then `lefthook install`,
  to run secret scanning on every commit.

### Application id

The Android application id is **`org.consolarr.app`**. It is a placeholder and
may change before the first public release: update `namespace` and
`applicationId` in both `apps/*/android/app/build.gradle.kts`, move
`MainActivity.kt` to the matching package directory, and update the splash/icon
resources if needed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), the
[Code of Conduct](CODE_OF_CONDUCT.md) and the [docs](docs/) (architecture,
patterns, Definition of Done). Report vulnerabilities privately as described
in [SECURITY.md](SECURITY.md), never in a public issue.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). Every source file carries an SPDX
header, enforced in CI. Bundled fonts (Inter, Noto Sans Arabic) are under the
SIL Open Font License; their licenses are shipped next to the font files.
