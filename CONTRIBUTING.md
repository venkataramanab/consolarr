# Contributing to Consolarr

Thanks for helping! Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first.

## Ground rules

1. **No secrets, ever.** Never commit keys, tokens, passwords, keystores,
   real hostnames, IP addresses, usernames or personal data. Fixtures use
   only `*.example` / `*.invalid` domains, RFC 5737 addresses (`192.0.2.x`)
   and obviously fake keys (`test-key-0000...`). Install the
   [lefthook](lefthook.yml) pre-commit hook (gitleaks) and CI will scan again.
2. **Test first.** Write the failing test, then the code.
3. **No hardcoded user-facing text.** Add strings to the feature's ARB files
   (every key needs an `@description`) and run `dart run melos run codegen`
   (generated output is never committed).
   The `consolarr_no_ui_string` lint enforces this; for genuinely non-UI
   strings use `// ignore: consolarr_no_ui_string -- <reason>`.
4. **No `print` / `debugPrint`** outside the logger; **no TLS trust APIs**
   (`badCertificateCallback`, `onBadCertificate`, `HttpOverrides`,
   `setTrustedCertificates`, `withTrustedRoots: false`) outside
   `packages/security/lib/src/http/secure_http_client_factory.dart`. These
   rules cannot be suppressed: CI fails on any `// ignore: consolarr_...`,
   `// ignore_for_file: consolarr_...` or `nosemgrep` that is not listed in
   `tools/ci/suppression_allowlist.txt` (changes there need CODEOWNERS
   review).
5. **No certificates or keys in the repository.** Tests that need a
   certificate generate it at test time into `**/test/.generated/`
   (git-ignored); committed `.pem`/`.key`/`.p12`/... files fail the repo guard
   unless listed in `tools/ci/forbidden_files_allowlist.txt`.
6. **Nothing before the first frame.** Initialize lazily; the first-frame
   test fails on network or database access.
7. **Accessibility and RTL are not optional.** Add your screen to the
   matrix tests (sizes x text scales x locales x themes) and the
   `meetsGuideline` checks.
8. Every source file starts with
   `SPDX-License-Identifier: GPL-3.0-or-later` (CI checks this).
9. Do not add telemetry SDKs. If ever needed they go in `apps/consolarr_play`
   only, behind explicit opt-in.

Follow the [Definition of Done](docs/contributing/definition-of-done.md); the
pull request template mirrors it.

## Workflow

```sh
flutter pub get
dart run melos run format
dart run melos run analyze
dart run melos run test
```

Use small, focused pull requests against `main`. Describe what changed and
why; do not paste private material into issues or PRs.

## Licensing of contributions

By contributing you agree that your contribution is licensed under
GPL-3.0-or-later. This project is independent and not affiliated with any of
the services it can control; do not copy code or assets from other client apps
(clean-room contributions only).
