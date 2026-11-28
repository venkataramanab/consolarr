# Vendored agent skills

Third-party skills are dependencies. Each one below was read in full (the
`SKILL.md` and every bundled file; none of these bundles contains a script or
any other file) before being copied unmodified. `SKILL.md` files are
byte-identical to upstream at the pinned commit; to update, re-review at the new
commit and replace them.

All upstream material is BSD-3-Clause, which is compatible with
GPL-3.0-or-later. The upstream licence texts are kept next to the skills:
[`LICENSE.flutter-agent-plugins`](LICENSE.flutter-agent-plugins) (Copyright 2026
The Flutter Authors) and [`LICENSE.dart-lang-skills`](LICENSE.dart-lang-skills)
(Copyright 2012, the Dart project authors). The project's GPL header rule does
not apply to these files; no GPL notice is added to someone else's work.

| Skill | Source | Commit | Licence | Why |
| --- | --- | --- | --- | --- |
| `flutter-add-widget-test` | `flutter/agent-plugins` | `ff6d472ee66dbed566c4500edee460c94fde0a02` | BSD-3-Clause | `WidgetTester` workflow. Wrap widgets in the project's themed test harness, not a bare `MaterialApp`. |
| `flutter-build-responsive-layout` | `flutter/agent-plugins` | `ff6d472ee66dbed566c4500edee460c94fde0a02` | BSD-3-Clause | `LayoutBuilder` / constraint guidance for tablets, foldables and large text. |
| `flutter-fix-layout-issues` | `flutter/agent-plugins` | `ff6d472ee66dbed566c4500edee460c94fde0a02` | BSD-3-Clause | Fixes overflow and unbounded-constraint errors. |
| `dart-write-documentation` | `dart-lang/skills` | `f84b16872b5d186f4e877511b49b93c204a1c4ef` | BSD-3-Clause | Effective Dart `///` conventions for public APIs. |

Where a skill's examples differ from the project rules (hardcoded text, stock
Material widgets), the project rules in `CLAUDE.md` and `docs/` win.
