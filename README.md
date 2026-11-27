# Consolarr

[![CI](https://img.shields.io/badge/CI-status%20badge%20placeholder-lightgrey)](.github/workflows/ci.yml)
<!-- Replace the badge above with the real workflow badge once the repository URL is final. -->

Consolarr is a free, open-source (GPL-3.0-or-later) Flutter app for Android
phones (minimum API 26) that remotely controls your **self-hosted** media
services: Sonarr, Radarr, qBittorrent, Transmission and Deluge.

> **Status: work in progress.** This repository currently contains the
> foundation only (monorepo, quality gates, test harness, app shell). There
> are no product features yet.

Consolarr is an independent project. It is **not affiliated with, endorsed by
or sponsored by** Sonarr, Radarr, the Servarr project, or any other client
app or service it can talk to. All product names belong to their owners.

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

See [docs/architecture.md](docs/architecture.md) for the dependency rules.

## Building

Prerequisites: the Flutter version pinned in [`.fvmrc`](.fvmrc)
(currently **3.50.1**, stable; use [FVM](https://fvm.app) or install that
version), the Android SDK, JDK 17+, and a recent Dart (ships with Flutter).

```sh
flutter pub get                  # resolves the whole workspace from the repo root
dart run melos run analyze       # format-agnostic analysis incl. custom lints
dart run melos run test          # unit, widget and golden tests with coverage
dart run melos run build:debug   # debug APKs for both apps
dart run melos run build:release # obfuscated arm64 release APKs
```

Debug builds need **no secrets** and telemetry is off. A **release build fails
without a git-ignored `key.properties`** so a debug-signed APK can never be
shipped by accident. For a local, non-distributable release build (CI does this
too) opt in explicitly:

```sh
ORG_GRADLE_PROJECT_consolarr.allowDebugSigning=true dart run melos run build:release
# or: add consolarr.allowDebugSigning=true to ~/.gradle/gradle.properties
```


Release builds use `--obfuscate --split-debug-info` (keep the generated
`build/debug-info` symbols to de-obfuscate stack traces).

Useful tasks:

- `dart run melos run l10n` regenerates localizations (edit the per-feature
  ARB files under `apps/consolarr/lib/features/<feature>/l10n/`, never the
  generated output; the `en_XA` pseudo-locale is generated, never hand-edited).
- `dart run melos run goldens:update` regenerates golden images.
- Copy `dart_defines.example.json` to `dart_defines.json` (git-ignored) only if
  you need build-time defines locally.
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

See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities privately as
described in [SECURITY.md](SECURITY.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). Every source file carries an SPDX
header, enforced in CI. Bundled fonts (Inter, Noto Sans Arabic) are under the
SIL Open Font License; their licenses are shipped next to the font files.
