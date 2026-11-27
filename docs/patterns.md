# Patterns (W3 walking skeleton)

Short, copyable conventions. Feature IDs (for example `SRV-06`) refer to the
product backlog; no requirement text is repeated here. Later work copies these
patterns instead of inventing new ones.

## 1. Where things live

```
packages/core            ServerProfile, AuthMode, AppError/ErrorCategory, Result
packages/security        TLS trust, pins, secret/pin stores, secure Dio factory
packages/arr_api         Sonarr client + models (pure Dart, hand written, tolerant)
packages/torrent_clients qBittorrent client + models (pure Dart)
packages/observability   event catalog (yaml -> typed API), breadcrumbs, redactor
packages/design_system   tokens, theme, reusable widgets (no l10n, no features)
apps/consolarr/lib/features/<feature>/
    data/          drift tables, repositories, storage adapters
    application/   Riverpod providers, controllers (no widgets)
    presentation/  screens and feature widgets (no I/O)
    l10n/          app_en.arb, app_ar.arb (merged by `melos run l10n`)
```

Dependency direction: `presentation -> application -> data -> packages`.
Widgets never call Dio, drift or storage directly.

## 2. Errors

* Every fallible call returns `Result<T>`; failures are `AppError` with an
  `ErrorCategory` (stable snake_case `code`). No exceptions cross a package API.
* `appErrorFromDio` (package `security`) is the only Dio-to-`AppError` mapper.
  The secure client puts typed errors (`CertificateDecisionRequired`,
  `TlsPinMismatch`, `CertificateExpired`, cleartext/redirect/size refusals) into
  `DioException.error`; the mapper passes them through.
* UI turns a category into copy with one function per feature
  (`<feature>/presentation/error_messages.dart`): a localized plain-language
  message plus a fix hint. One ARB key pair per category.
* `AppError.debugDetail` is developer-only, secret-free, never shown.

## 3. Providers (Riverpod)

* Providers are created lazily; nothing reads them before the first frame.
* `<feature>/application/<feature>_providers.dart` holds the providers;
  repositories are plain classes behind a provider so tests override them.
* Async data uses `AsyncNotifier`; never swallow errors into `null`.
* Infrastructure seams (`secretStoreProvider`, `pinStoreProvider`,
  `secureHttpClientFactoryProvider`, `databaseProvider`, `clockProvider`) live
  in `lib/src/providers.dart` so tests and the Play entry point can override.

## 4. Secrets

* The profile never holds secrets. Secrets live in `SecretStore` under
  `<serverId>/api_key`, `<serverId>/username`, `<serverId>/password`,
  `<serverId>/header/<name>`; the drift row only references the server id.
* A missing secret means "needs credentials" (Keystore loss): the server is
  marked, the UI asks for re-entry. Never throw.
* Secret fields use `SecretTextField` (masked, reveal toggle); the editor route
  sets the platform secure flag while any secret is revealed.

## 5. TLS and HTTP

* All HTTP clients come from `SecureHttpClientFactory.create(profile)`
  (Dio) - also for images. Never construct `HttpClient`/`Dio` elsewhere.
* TOFU: `CertificateDecisionRequired` -> trust sheet -> on accept the feature
  code builds `UserPinConfirmation.userAccepted(...)` (only allowed under
  `apps/*/lib/features/`) and calls `PinStore.write`, then retries.
* API keys go in headers (`X-Api-Key`), never in URLs, including image URLs.

## 6. Observability

* Events are declared in `packages/observability/events/*.yaml`; the committed
  generator writes the typed API. Parameters are closed enums, ints or bools;
  there is no free-text parameter, so URLs, hosts, keys, usernames and titles
  cannot be reported by construction.
* Names: `snake_case`, noun then past-tense verb or state (`server_added`,
  `connection_test_result`).
* Navigation and API error categories are recorded as breadcrumbs.

## 7. UI

* Strings: per-feature ARB files with `@description`; ICU plurals.
* Components receive already-localized strings as parameters.
* Floating glass bars only over scrolling lists; content is padded by the
  measured bar height; solid fallback via `ConsolarrEffects`.
* State is always icon + text, never colour alone. Progress rows expose state
  and percentage in their semantics label.

## 8. Tests

* Test first. Packages: unit tests with local `HttpServer` (certificates are
  generated at test time into `test/.generated/`, which is git-ignored).
* Widgets: every state through `pumpMatrix` (sizes x text scale x locales),
  plus `expectAccessible`. Goldens only where listed in the PR.
* Network scenarios use the harness `FaultInjectingAdapter`.

## 9. Concrete recipes (copy these)

**A new service feature** (`features/<name>/`):
1. `data/<name>_repository.dart`: takes the client (built from
   `activeConnectionProvider(kind)`), returns `Result`, writes the last good
   payload to `PayloadCache` (`<name>.<resource>` key) and falls back to it for
   network/timeout/5xx/not-found/parse failures only. Never fall back for
   `auth_failed`, `unsupported_version` or TLS errors.
2. `application/<name>_providers.dart`: one `AsyncNotifier` exposing a sealed
   state (`NoServer`, `Failure(AppError)`, `Data(snapshot)` with `isOffline`).
   Refresh keeps existing content. Disable Riverpod's automatic retry
   (`retry: (_, _) => null`) for providers that surface `AppError`s.
3. `presentation/<name>_screen.dart`: `FloatingTopBarScaffold` + a
   `bodyBuilder` that uses the padding it is given; the shell raises
   `MediaQuery.padding.bottom` by the floating nav bar's measured height.
4. Strings in `l10n/app_{en,ar}.arb`, then `melos run l10n`.
5. Tests: repository (fake adapter), notifier, every state under `pumpMatrix`
   with `harnessApp` + `ProviderScope(overrides: ...)`, a11y at scale 2.0 in
   `ar` and `en_XA`, 0/10,000-item extremes, 1-2 goldens.

**Provider conventions:** `<thing>Provider`; infrastructure seams in
`lib/src/providers.dart`; anything that touches the database or network is
reached only after `firstFrameDoneProvider` is true (use `uiServersProvider`
rather than `serversProvider` in widgets visible on the first frame).

**Error mapping:** package clients return `Result<T>`; the Dio mapper is
`appErrorFromDio`; the UI maps `AppError` to copy with
`connectionErrorMessage(l10n, error)` (message + fix hint per category).

**Event naming:** `snake_case`, declared in
`packages/observability/events/<area>.yaml`; regenerate with
`melos run events` (output `lib/src/events/catalog.dart`, committed; a test
fails when it drifts). Parameters are enums/ints/bools only.

**Drift:** tables and the database live in `lib/src/database/app_database.dart`.
The generated `app_database.g.dart` is **not** committed (the repo guard
rejects tracked `*.g.dart`); run `melos run codegen` after `pub get` (CI does
it in the `setup-flutter` action). Bump `schemaVersion` and add a migration
for every schema change.

**Images:** use `SecureNetworkImage` (loads through the server's secure Dio,
auth in headers, validates magic bytes, decodes at the `cacheWidth` that
`PosterCard` supplies). Never `Image.network`.

**TLS/TOFU flow:** see `packages/security` doc comments. A pinned server uses
an empty trust set so only the exact pinned certificate completes the
handshake (before any request bytes); an unpinned untrusted server fails with
`CertificateDecisionRequired`; the feature UI shows `CertificateTrustSheet`,
builds `UserPinConfirmation.userAccepted` in its accept handler and retries on
the same Dio.

## 10. Nightly integration

`tools/integration/` starts digest-pinned Sonarr, qBittorrent and toxiproxy
containers, seeds them (one series needs outbound internet for Sonarr's
metadata lookup; the torrent is generated locally) and
`apps/consolarr/integration_test/servers_to_lists_test.dart` adds both servers
and opens both lists on the emulator, then runs a latency + connection-drop
scenario.
