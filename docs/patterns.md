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
