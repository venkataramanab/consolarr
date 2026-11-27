## Summary

<!-- What changed and why. Do not paste secrets, real hostnames or personal data. -->

## Definition of Done

- [ ] **Security / no-leak:** no secrets, real hosts, IPs, usernames or
      personal data anywhere (fixtures: `*.example`, `*.invalid`, `192.0.2.x`,
      `test-key-0000...`). gitleaks is clean. Manifest stays hardened. New
      logging goes through the redacting logger. Security-relevant logic has
      tests, including failure and mismatch cases.
- [ ] No secrets, real hosts or personal data in code, fixtures, screenshots
      or PR text.
- [ ] **Performance:** no work before the first frame; everything lazy. The
      first-frame test passes. Debug and release APKs build without secrets;
      the APK size gate (arm64 release <= 20 MiB) passes.
- [ ] **Observability:** only interfaces and no-ops in the foss app; no
      telemetry SDK dependencies. Anything that could be reported passes
      through `Redactor` first.
- [ ] **TDD:** tests were written first; every touched package has tests;
      harness changes have self-tests.
- [ ] **Accessibility:** every interactive element has a name, role and state;
      tap targets >= 48dp; text contrast passes; screens pass the
      `meetsGuideline` checks at text scale 2.0 (including `ar` and `en_XA`);
      no information by colour alone; reduced motion respected.
- [ ] **i18n:** zero hardcoded user-facing text; keys have `@description`;
      the l10n key check passes; layouts survive `en_XA`, large text and the
      RTL locale (`ar`).
- [ ] `dart run melos run analyze` and `dart run melos run test` pass locally
      and CI is green.
- [ ] Docs updated where behaviour or structure changed.
