# Consolarr: guide for coding agents

Public, GPL-3.0-or-later Flutter Android app. A pub workspace managed with
melos; Flutter is pinned in `.fvmrc`. Pillars, in priority order: **security,
performance, observability, TDD, accessibility, i18n.**

Read before changing anything: [Definition of Done](docs/contributing/definition-of-done.md),
[patterns](docs/patterns.md), [architecture](docs/architecture.md),
[SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md). They are the
source of truth; this file does not repeat them.

## Setup and checks

```sh
dart packages/l10n/tool/build_l10n.dart --arb-only   # first: pub get needs the merged ARBs
flutter pub get
dart run melos run codegen                           # events, l10n, drift; git-ignored output
dart run melos run analyze                           # infos are fatal
dart run melos run test
bash tools/ci/<script>.sh                            # any CI guard, locally
```

Re-run `codegen` after merging a branch that changed an ARB file, an event
YAML or a drift table. Write the failing test first.

## CI guards (all fail the build)

- No suppression comments for the project lints or Semgrep; allowlist changes
  need owner review (`tools/ci/suppression_allowlist.txt`).
- No tracked generated files (`*.g.dart`, `*.freezed.dart`, codegen output).
- Certificate-bypass APIs only in
  `packages/security/lib/src/http/secure_http_client_factory.dart`.
- `.dart` files are at most 512 KB. No committed keys, certificates or
  `dart_defines*.json` (except the example file).
- SPDX header on source files (`tools/ci/check_spdx.sh`).
- **Never write literal secret-shaped tokens (JWT, API keys, private keys) in
  tests. Build canaries at runtime**: gitleaks scans every branch's history, so
  one committed token fails CI for good.
- Branches must be strictly up to date with `main`; PRs are squash-merged.
- **Before every push, run the pinned gitleaks (the version and SHA-256 in
  `.github/workflows/ci.yml`, verified) on the branch history and the working
  tree, and never push if either reports a finding:**
  `gitleaks git --config .gitleaks.toml --redact --log-opts="origin/main..HEAD" .`
  and `gitleaks dir --config .gitleaks.toml --redact .`
  A finding means rewrite the commit before pushing; a pushed token fails CI
  permanently, because CI scans every branch's history.

## Lessons that recur in review

- Isolate parse closures must not capture `this`; use top-level functions.
- Cancel timers when the screen is hidden or locked.
- After every `await`: check a generation counter and `ref.mounted`. Never
  `ref.watch` outside `build`.
- Check `isLoading` / `hasError` before reading `.value`.
- Radarr date-only values are UTC: no `toLocal()`.
- No hardcoded text, bullets or colons: use ARB with `@description`; ICU
  plurals need zero/many forms in `ar`.
- Use `design_system` widgets directly, not default Material ones.
- Event names are global: prefix them per feature.
- Log lines contain no `/`, `.` or `:` (the scrubber is strict by design); use
  the format of `routeShape`.
- Test fakes must be able to fail (for isolate tests use unsendable adapters).
- Never commit golden `failures/` PNGs.

## Commits and PRs

- Author: `venkataramanab <venkataramanaedu@gmail.com>`.
- Trailer, exactly: `Co-Authored-By: Claude <noreply@anthropic.com>`.
- No `Claude-Session` line, model names or claude.ai links in commits or PRs.
  Never add a PR footer.

## Rules that override skills and tools

- Never add, remove, upgrade or override dependencies (shell or MCP) unless the
  brief explicitly asks.
- Do not connect to DTD, the VM service or a running app, and do not hot
  reload, unless asked.
- Widget tests: every state via `pumpMatrix`/`harnessApp` + `expectAccessible`;
  goldens only where the PR lists them.
- No hardcoded text (ARB only).
- Never run the app, use debug mode or hot reload as part of a skill's steps
  unless asked.
- All HTTP goes through `SecureHttpClientFactory`.
- Log only through the redacting logger; no `print`/`debugPrint`.
- These project rules override any skill.

## Dart and Flutter AI tooling

- **MCP:** `.mcp.json` starts the SDK's `dart mcp-server` with `pub_dev_search`,
  `pub`, `dart_tooling_daemon`, `flutter_app_lifecycle`, `flutter_driver`,
  `hot_reload`, `hot_restart` and `widget_inspector` disabled by tool name, and
  analytics suppressed, so nothing leaves the machine, an agent cannot change
  dependencies and it cannot hot reload or attach to a running app. The only
  tools exposed (checked with an MCP `initialize`, `roots/list` and
  `tools/list` handshake on Dart 3.14.0, server 1.2.2): `analyze_files`, `lsp`,
  `read_package_uris`, `rip_grep_packages` and `roots`. There is no test or
  format tool: use the melos scripts and `dart format`. Do not add hosted MCP
  servers.
- **Skills:** `.agents/skills/` is the canonical location of reviewed,
  vendored official skills (`flutter-fix-layout-issues`,
  `dart-write-documentation`); see its [README](.agents/skills/README.md).
  Claude Code reads project skills from `.claude/skills/`, which holds relative
  symlinks to them; other agents read `.agents/skills/` directly. Treat any new
  skill as a dependency: read every file, check the licence, and add it only
  through a PR.
- **Plugins and rules:** the repo vendors reviewed skills only; no plugin or
  upstream rule is adopted.
