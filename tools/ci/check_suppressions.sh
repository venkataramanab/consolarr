#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fails when a security lint is switched off. The project's own analyzer rules
# (consolarr_*) and Semgrep rules must not be silenced with `// ignore:`,
# `// ignore_for_file:`, analysis_options overrides or `nosemgrep` comments,
# except for the exact (file, rule) pairs listed in
# tools/ci/suppression_allowlist.txt. Changes to that file need a CODEOWNERS
# review (see .github/CODEOWNERS).
#
# Usage: tools/ci/check_suppressions.sh [repo-root]   (default: git toplevel)
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"

allowlist=tools/ci/suppression_allowlist.txt
self=tools/ci/check_suppressions.sh

# What counts as a suppression (matched anywhere on a line, so a comment that
# follows code or a string literal on the same line is found too, and doc
# comments and block comments are included):
#  * `// ignore:` / `// ignore_for_file:` naming a consolarr_ rule, or the
#    blanket `type=lint`, which silences every lint including ours;
#  * any `nosemgrep` or the short form `nosem`, in `//` or `/* */` comments.
# Quoted mentions in strings are false positives on purpose: a guard that
# trusts the surrounding syntax is a guard that can be bypassed.
# CI also runs semgrep with `--disable-nosem`, so a comment cannot hide a
# finding even if one were allowlisted by mistake.
word='(^|[^[:alnum:]_])'
endw='([^[:alnum:]_]|$)'
dart_pattern="(//|/\\*)[[:space:]]*ignore(_for_file)?[[:space:]]*:.*(consolarr_|type[[:space:]]*=[[:space:]]*lint)|${word}nosem(grep)?${endw}"
yaml_pattern="^[^#]*consolarr_(no_ui_string|bad_certificate_callback|no_print)|#.*${word}nosem(grep)?${endw}"

hits=$(
  {
    git grep -n -I -E "$dart_pattern" -- '*.dart' ':!tools/ci/*' || true
    git grep -n -I -E "$yaml_pattern" -- '*.yaml' '*.yml' ':!tools/semgrep/*' || true
  } | sort -u
)

status=0

# The shared test harness is library code that every test depends on, so it
# takes no analyzer suppression at all, whatever the rule: the pattern above
# only names project rules, so `// ignore: invalid_use_of_visible_for_testing_member`
# once passed unnoticed. Not allowlistable; fix the code instead.
harness_hits=$(git grep -n -I -E '(//|/\*)[[:space:]]*ignore(_for_file)?[[:space:]]*:' \
  -- 'packages/test_harness/lib/*.dart' || true)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "::error file=${hit%%:*}::Analyzer suppression in test_harness library code. Fix the code instead; it cannot be allowlisted."
  echo "  $hit"
  status=1
done <<< "$harness_hits"

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file=${hit%%:*}
  # Which rules does this line mention? `nosem` / `nosemgrep` count as
  # `nosemgrep`, `type=lint` as its own rule.
  rules=$(printf '%s\n' "$hit" | cut -d: -f3- \
    | grep -o -E "consolarr_[a-z_]+|${word}nosem(grep)?${endw}|type[[:space:]]*=[[:space:]]*lint" \
    | sed -E -e 's/^[^[:alnum:]_]//' -e 's/[^[:alnum:]_]$//' -e 's/^nosem$/nosemgrep/' -e 's/[[:space:]]//g' \
    | sort -u || true)
  [ -n "$rules" ] || rules=unknown
  for rule in $rules; do
    if ! grep -E -q "^${file//./\\.}[[:space:]]*\|[[:space:]]*${rule}[[:space:]]*(#.*)?$" "$allowlist" 2>/dev/null; then
      echo "::error file=$file::Unlisted suppression of '$rule'. Fix the code instead, or (with CODEOWNERS review) list it in $allowlist."
      echo "  $hit"
      status=1
    fi
  done
done <<< "$hits"

[ "$status" -eq 0 ] && echo "No unlisted lint suppressions."
exit "$status"
