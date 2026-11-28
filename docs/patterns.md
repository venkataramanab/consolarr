# Patterns (W3 walking skeleton, updated in W3b)

Short, copyable conventions. Feature IDs (for example `SRV-06`) refer to the
product backlog; no requirement text is repeated here. Later work copies these
patterns instead of inventing new ones.

## 1. Where things live

```
packages/core            ServerProfile, AuthMode, AppError/ErrorCategory,
                         kOfflineFallbackCategories, Result, ParsedRows
packages/security        TLS trust, pins, secret/pin stores, secure Dio factory
packages/arr_api         ArrClientBase (+ shared models), SonarrClient (hand written, tolerant)
packages/torrent_clients TorrentClient (+ actions), QBittorrentClient (pure Dart)
packages/observability   event catalog (yaml -> typed API), breadcrumbs, redactor
packages/design_system   tokens, theme, reusable widgets (no l10n, no features)
apps/consolarr/lib/
  features/<feature>/
    <feature>_routes.dart   the feature's AppDestination(s)
    data/                   drift tables (<feature>_tables.drift, <feature>_migration.dart),
                            repositories, storage adapters
    application/            Riverpod providers, controllers (no widgets)
    presentation/           screens and feature widgets (no I/O)
    l10n/                   app_en.arb, app_ar.arb
  shared/                   used by several features
    errors/                 connectionErrorMessage (AppError -> copy)
    l10n/                   app_{en,ar}.arb (connection errors, common actions),
                            reserved_keys.txt
  src/                      app wiring: providers.dart (infrastructure seams),
                            router.dart, navigation/, database/, cache/, images/
```

Dependency direction: `presentation -> application -> data -> packages`.
Widgets never call Dio, drift or storage directly. Features never import each
other's `application`/`data`; they share through `shared/` and `src/`.

**Recorded exception (settings).** `features/settings` reads the server list
for the connection check and for scrubbing known values out of the diagnostics
bundle, so it imports `serversProvider`, `serverRepositoryProvider` and
`ServerRepository` from `features/servers`, `uiServersProvider` from
`features/shell` and `ScreenTracker` from `features/servers/presentation`.
They stay where they are until the open Sonarr, Torrents and Radarr branches
have merged (all of them import these by path); moving them to `lib/src/` is a
mechanical follow-up. Do not add further cross-feature imports.

## 2. Errors

* Every fallible call returns `Result<T>`; failures are `AppError` with an
  `ErrorCategory` (stable snake_case `code`). No exceptions cross a package API.
* `appErrorFromDio` (package `security`) is the only Dio-to-`AppError` mapper.
  The secure client puts typed errors (`CertificateDecisionRequired`,
  `TlsPinMismatch`, `CertificateExpired`, cleartext/redirect/size/deadline
  refusals) into `DioException.error`; the mapper passes them through.
* `SecretStore.read` throws `SecretStoreUnavailable` when the Keystore cannot
  be read. The **pin path fails closed** (the request is blocked, never a
  first-use trust prompt); only the credential path maps it to "needs
  credentials".
* **Copy:** `connectionErrorMessage(l10n, error)` in
  `lib/shared/errors/connection_error_message.dart` is the one function that
  turns an `AppError` into a message plus fix hint (`connError<Category>Message`
  / `Hint` in `shared/l10n`). Use it unless a screen needs its own headline
  (the Sonarr library has `sonarrErrorCopy` for that; do not add more copies).
* `AppError.debugDetail` is developer-only, secret-free, never shown.
* **Offline fallback:** only the categories in `kOfflineFallbackCategories`
  (unreachable, timeout, 5xx, not found, parse, too large) may fall back to
  cached or last-good data. `auth_failed`, `unsupported_version` and every TLS
  category are shown as such, never hidden behind old data.
* **Per-row tolerance:** list parsers use `parseRowsTolerant` / `parseArrList`:
  malformed rows are skipped and only their *count* is logged (clients take an
  `onRowsSkipped` callback); a payload where no row parses is `parse_error`.

## 3. Providers (Riverpod) and state

* Providers are created lazily; nothing reads them before the first frame
  (`uiServersProvider` is the first-frame-safe server list).
* `<feature>/application/<feature>_providers.dart` holds the providers;
  repositories are plain classes behind a provider so tests override them.
* **Canonical state: a sealed class** exposed by an `AsyncNotifier`:
  `NoServer`, `Data(...)` (with an offline marker carrying the `AppError`),
  and, for failures that must block, `Failure(AppError)` *or* the provider's
  own `AsyncError` (torrents use `AsyncError`; Sonarr's `LibraryFailure` is a
  state). Never a bag of booleans.
* **A server switch is a reload.** Riverpod keeps the previous value through
  `AsyncLoading` and `AsyncError`, so a screen checks, in order,
  `isLoading` -> skeleton, `hasError` -> error, then `value`. Reading `.value`
  first shows the previous server's data as current.
* **Stale writes.** A notifier bumps a generation counter in `build()`;
  `refresh()` captures it before each `await` and drops the result when
  `!ref.mounted` or the generation moved. Overlapping refreshes are coalesced
  per generation, and a refresh during a reload is ignored.
* Disable Riverpod's automatic retry (`retry: (_, _) => null`) for providers
  that surface `AppError`s.
* **Live connection.** `activeConnectionProvider(kind)` rebuilds whenever
  `ServerRepository.watchConnectionKey(kind)` changes: the active server id
  plus a revision that `save()` bumps. Set-active, the switcher and credential
  edits therefore need no manual `invalidate`. (It subscribes with a plain
  stream listener: Riverpod pauses dependencies of providers nobody listens
  to yet.)
* Infrastructure seams (`secretStoreProvider`, `pinStoreProvider`,
  `secureHttpClientFactoryProvider`, `databaseProvider`, `clockProvider`,
  `monotonicClockProvider`, `secureScreenProvider`, `loggerProvider`) live in
  `lib/src/providers.dart`; tests and the Play entry point override them.
* **Settings are read once.** `storedRowsProvider` reads the settings table
  after the first frame; `SettingsNotifier` and the consent store share that
  one read. A failed read is retried once; after that the app **fails closed**
  (`LockPhase.loadFailed`: content hidden, window secure, retry button).
* **Consent.** `consentManagerProvider` loads the stored choice right after the
  first frame, so consent applies from startup. Entry points (Play) override
  `rawCrashReporterProvider` / `rawAnalyticsProvider` only, never the gated
  `crashReporterProvider` / `analyticsProvider` (a test guards this). While
  consent is off the raw sinks get no call at all.
* **The window secure flag is reference counted by owner**
  (`SecureScreen.setSecure(secure:, owner:)`): the app lock and "block
  screenshots" are one owner, every revealed secret field tracker another.
  Never clear the flag directly.
* **Settings setters** apply the value, write it and revert that field if the
  write fails (logging only the error type); they return whether it was stored.
* **Time away** (the app lock delay) uses the monotonic clock together with the
  wall clock: the longer of the two counts, so changing the wall clock cannot
  extend it.

## 4. Secrets

* The profile never holds secrets. Secrets live in `SecretStore` under
  `<serverId>/api_key`, `<serverId>/username`, `<serverId>/password`,
  `<serverId>/header/<name>`; the drift row only references the server id.
* A missing or unreadable secret means "needs credentials": the server is
  marked, the UI asks for re-entry. Never throw.
* **Secrets never follow an address change.** When scheme, host or port
  changes, the editor and the connection test require the secrets again and
  the repository drops the stored ones that are not re-supplied. Editing the
  identity (kind, address, path prefix) also clears the cached payloads and the
  old pins. `save()` keeps the alternate address.
* **Sonarr and Radarr always need the API key** (their API has no username and
  password login). A username and password for a reverse proxy in front of
  them is an optional extra: it is stored under the same
  `<serverId>/username` / `<serverId>/password` keys and sent as
  `Authorization: Basic` *in addition to* `X-Api-Key`
  (`ServerEntry.proxyLogin` is derived from the stored secrets, so there is no
  profile column). Profiles saved in the old `basic` or `none` mode open in the
  editor with the key required and keep their login as the proxy login.
* Secret fields use `SecretTextField` (masked, reveal toggle); the editor route
  sets the platform secure flag while any secret is revealed.
* Addresses: ports must be 1..65535, no backslash, no non-ASCII host (enter the
  punycode form); each has its own localized validation message.

## 5. TLS and HTTP

* All HTTP clients come from `SecureHttpClientFactory.create(profile)`
  (Dio) - also for images. Never construct `HttpClient`/`Dio` elsewhere.
* Limits (`HttpLimits`): connect/send/receive timeouts are per-chunk;
  `requestDeadline` bounds the whole request (all redirect hops and the body);
  the API body cap is 16 MiB (images raise it per request with
  `maxResponseBytesKey`).
* TOFU: `CertificateDecisionRequired` -> trust sheet -> on accept the feature
  code builds `UserPinConfirmation.userAccepted(...)` (only allowed under
  `apps/*/lib/features/`) and calls `PinStore.write`, then retries.
* API keys go in headers (`X-Api-Key`), never in URLs, including image URLs.

## 6. Per-kind registries (no switches on `ServiceKind`)

One line per new service, in one place each:

| What | Where | Key |
| --- | --- | --- |
| Credential headers | `servers/application/auth_headers.dart` `authHeaderBuilders` | `ServiceKind` |
| Connection probe (test + health) | `servers/application/connection_tester.dart` `connectionProbes` | `ServiceKind` |
| Torrent client factory | `torrents/application/torrent_client_registry.dart` `torrentClientFactories` | `ServiceKind` |
| Editor picker | `servers/presentation/service_kind_info.dart` `supportedServiceKinds` | list |

A kind without a probe is **not** reported as `unsupported_version`; the tester
returns an explicit "no probe registered" failure (the picker only offers
registered kinds). `TorrentClient` declares the actions (pause, resume, delete,
add magnet/URL/file, global limits, detail); mix in `UnsupportedTorrentActions`
to answer the ones a client lacks with the typed `UnsupportedAction`. `ArrApi`
declares the shared lists (`qualityProfiles`, `rootFolders`, `tags`); fakes mix
in `EmptyArrLists`.

## 7. Navigation

* A destination is an `AppDestination` (`id`, `route`, icons, `label` accessor,
  `kinds`, `screen`, `switcherKind`, `builder`), contributed by
  `features/<f>/<f>_routes.dart`.
* `lib/src/navigation/destinations.dart` lists them in bar order (a slot per
  planned feature is marked there). The router builds one shell branch per
  entry and the bar is built from the same list: no enum, no positional
  coupling.
* `AppDestination.children` are the branch's child routes. Their paths are
  **relative to `route`** (for example `series/:id`, not `/sonarr/series/:id`).
  A child renders inside the shell with the bar visible; a full-screen flow
  sets `parentNavigatorKey: rootNavigatorKey`. Sheets and menus
  (`showGlassSheet`, `showNestedMenu`) open on the root navigator, above the
  bar.
* **Polling pauses while the app is locked.** The content stays mounted
  (hidden) behind the lock, so every timer or poll that talks to a server must
  skip its tick while `appLockedProvider` is true (and resume after unlock).
* A destination with `kinds` is offered once a server of any of those kinds
  exists; the open branch is always shown, so the bar never highlights another
  tab for the screen you are on. `routeForKind(kind)` replaces switches that
  mapped a kind to a route.

## 8. Observability

* Events are declared in `packages/observability/events/<area>.yaml`
  (`servers`, `sonarr`, `radarr`, `torrents`, `settings`); parameters are
  closed enums, ints or bools, so URLs, hosts, keys, usernames and titles
  cannot be reported by construction. Every planned `screen_name` and every
  `service_kind_param` value is declared up front.
* Names: `snake_case`, noun then past-tense verb or state (`server_added`,
  `connection_test_result`).
* Navigation and API error categories are recorded as breadcrumbs. Logs go
  through `loggerProvider` (redacted); log counts and categories only.
* **Request log.** Every server connection (`activeConnectionProvider`) and
  every connection test carries a `LoggingInterceptor`
  (`lib/shared/logging/`): `GET /api/v3/movie/{id} -> 200, 12ms` at debug,
  `... failed category=auth_failed status=401, 12ms` at warning. It reads the
  method, the path (reduced by `routeShape`: only plain route words survive,
  ids/hashes/titles become `{id}`), the status and the clock, never the host,
  port, query, headers, bodies or credentials. App-level lines
  (`server_switch`, `needs_credentials`, `offline_fallback`,
  `connection_test`) are built in `shared/logging/log_events.dart` from closed
  values only. Artwork failures are visible the same way (the image loader
  uses the connection's Dio); a 200 that is not an image is logged by
  `LoggingInterceptor.artworkRejected`.

## 9. UI

* Strings: per-feature ARB files with `@description`; ICU plurals; numbers
  through ARB number-format placeholders (`decimalPattern` /
  `decimalPatternDigits`) so digits localize.
* Shared strings (connection errors, common actions) live in
  `lib/shared/l10n`. `reserved_keys.txt` lists keys declared ahead of use: the
  key test tolerates them unused and fails once one is used (remove its line).
* Components receive already-localized strings as parameters.
* Floating glass bars only over scrolling lists; content is padded by the
  measured bar height; solid fallback via `ConsolarrEffects`.
* State is always icon + text, never colour alone. Progress rows expose state
  and percentage in their semantics label; decorative graphs are excluded from
  semantics and repaint on their own `RepaintBoundary`.
* Images: `SecureNetworkImage` through the server's secure Dio, wrapped in
  `ResizeImage` at the `cacheWidth` that `PosterCard` supplies; the image cache
  is capped at 50 MB after the first frame. Never `Image.network`.

## 10. Generated code (never committed)

`dart run melos run codegen` generates, in this order: the event catalog
(`packages/observability/lib/src/events/catalog.dart`), the merged
localizations (`packages/l10n/lib/arb/*`, `lib/src/generated/*`, including the
`en_XA` pseudo-locale) and the drift code (`app_database.g.dart`). All are
git-ignored and the repo guard rejects tracked copies. CI runs it in the
`setup-flutter` action before analyze, test and build.

**Regenerate after merging** a branch that changed an ARB file, an event YAML
or a drift table, and after every fresh `pub get`:
`dart run melos run codegen`. The l10n and event tests fail with that hint
when the generated files are stale.

Per-feature files so parallel work does not collide:

* ARB: `features/<f>/l10n/app_{en,ar}.arb` (keys unique across features);
* events: `packages/observability/events/<area>.yaml`;
* drift: `features/<f>/data/<f>_tables.drift` and
  `<f>_migration.dart`, one pre-allocated schema version per feature
  (`lib/src/database/migrations.dart`: 2 sonarr, 3 radarr, 4 torrents,
  5 settings). A feature creates its tables only in its own step; a later
  change appends a new slot.

## 11. Tests

* Test first. Packages: unit tests with local `HttpServer` (certificates are
  generated at test time into `test/.generated/`, which is git-ignored).
* Widgets: every state through `pumpMatrix` (sizes x text scale x locales),
  plus `expectAccessible`; stress variant: 320x568, scale 2.0, `ar` and
  `en_XA`. Every design-system widget needs a sample in `componentSamples()`
  (a test enforces it). Goldens only where listed in the PR.
* **Provider-transition tests** (switching servers, credential edits) use the
  real providers and a real screen, not hand-built fake states.
* Network scenarios use the harness `FaultInjectingAdapter`.
* The first-frame test observes provider creation (database, repository,
  pins, clients) as well as I/O.

## 12. Concrete recipes (copy these)

**A new service feature** (`features/<name>/`):
1. `data/<name>_repository.dart`: takes the client (built from
   `activeConnectionProvider(kind)`), returns `Result`, writes the last good
   payload to `PayloadCache` (`<name>.<resource>` key) and falls back to it
   only for `kOfflineFallbackCategories`.
2. `application/<name>_providers.dart`: one `AsyncNotifier` exposing a sealed
   state (section 3), generation guard, `retry: (_, _) => null`.
3. `presentation/<name>_screen.dart`: `FloatingTopBarScaffold` + a
   `bodyBuilder` that uses the padding it is given; check `isLoading`,
   `hasError`, then `value`.
4. `<name>_routes.dart`: the `AppDestination`; add it to `appDestinations`.
5. Strings in `l10n/app_{en,ar}.arb`, events in the area YAML, registry
   entries (section 6), then `dart run melos run codegen`.
6. Tests: repository (fake adapter), notifier, provider-transition tests, every
   state under `pumpMatrix` with `harnessApp` + `ProviderScope(overrides:)`,
   a11y at scale 2.0 in `ar` and `en_XA`, 0/10,000-item extremes, 1-2 goldens.

**Provider conventions:** `<thing>Provider`; infrastructure seams in
`lib/src/providers.dart`; anything that touches the database or network is
reached only after `firstFrameDoneProvider` is true.

**TLS/TOFU flow:** see `packages/security` doc comments. A pinned server uses
an empty trust set so only the exact pinned certificate completes the
handshake (before any request bytes); an unpinned untrusted server fails with
`CertificateDecisionRequired`; the feature UI shows `CertificateTrustSheet`,
builds `UserPinConfirmation.userAccepted` in its accept handler and retries on
the same Dio.

## 13. Nightly integration

`tools/integration/` starts digest-pinned Sonarr, qBittorrent and toxiproxy
containers, seeds them (one series needs outbound internet for Sonarr's
metadata lookup; the torrent is generated locally) and
`apps/consolarr/integration_test/servers_to_lists_test.dart` adds both servers
and opens both lists on the emulator, then runs a latency + connection-drop
scenario.

## 14. Size budget

The release arm64 APK has a 20 MiB gate (`tools/ci/check_apk_size.sh`, with a
warning from 90%). Native libraries are stored compressed
(`packaging.jniLibs.useLegacyPackaging`), plugin libraries of other ABIs are
dropped when `--target-platform` is given, and Inter is subset to Latin
(`design_system/assets/fonts/README.md`; Arabic uses the system fonts).
Android resources are limited to `en` and `ar` (`androidResources.localeFilters`
in both flavors), which drops the ~70 translations AndroidX libraries bring.
Sharing text uses a first-party method channel (`consolarr/share`,
`ACTION_SEND`) instead of a plugin. `local_auth` (androidx.biometric, the app
lock) is the one deliberate size cost; see the PR for its budget exception.
