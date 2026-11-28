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
| `flutter-fix-layout-issues` | `flutter/agent-plugins` | `ff6d472ee66dbed566c4500edee460c94fde0a02` | BSD-3-Clause | Fixes overflow and unbounded-constraint errors. |
| `dart-write-documentation` | `dart-lang/skills` | `f84b16872b5d186f4e877511b49b93c204a1c4ef` | BSD-3-Clause | Effective Dart `///` conventions for public APIs. |

## Discovery

This directory is canonical. Claude Code discovers project skills only in
`.claude/skills/`, where each kept skill is a relative symlink
(`.claude/skills/<name>` to `../../.agents/skills/<name>`), so no content is
duplicated. Other agents that follow the `.agents/skills/` convention read this
directory directly.

## Reviewed and removed

| Skill | Why it was removed |
| --- | --- |
| `flutter-add-widget-test` | Its workflow conflicts with the project's `pumpMatrix`/`harnessApp` + `expectAccessible` testing. |
| `flutter-build-responsive-layout` | Generic, and its examples break project rules (hardcoded text, stock Material widgets). |

Where a skill's examples differ from the project rules (hardcoded text, stock
Material widgets), the project rules in `CLAUDE.md` and `docs/` win.
