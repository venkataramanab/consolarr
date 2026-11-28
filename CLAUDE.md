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

## Dart and Flutter AI tooling

- **MCP:** `.mcp.json` starts the SDK's `dart mcp-server` (analyzer, tests,
  formatting, symbol lookup, runtime inspection). `pub_dev_search` is disabled
  and analytics are suppressed so nothing leaves the machine. Do not add
  hosted MCP servers.
- **Skills:** `.agents/skills/` holds reviewed, vendored official skills; see
  its [README](.agents/skills/README.md). Treat any new skill as a dependency:
  read every file, check the licence, and add it only through a PR.
- **Rules:** the official `flutter/agent-plugins` repo ships one rule
  (proactive hot reload). It is not adopted: cloud sessions have no running
  app, and it makes the agent act unprompted.
- **Optional plugin (local only, not installed by the repo):**
  `claude plugin marketplace add flutter/agent-plugins`, then
  `claude plugin install dart-flutter@dart-flutter`. The repo already carries
  the reviewed skills and the MCP config, so the plugin is not needed.
- Skills never override the project rules above: if a skill suggests
  suppressing a lint, adding a dependency or using stock Material widgets,
  follow the project rule.
