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

# ignore / ignore_for_file comments naming a consolarr_ rule, any nosemgrep,
# and analysis_options overrides that mention a consolarr_ rule id.
# (A directive is a `//` comment that is not a doc comment (`///`) and not
# quoted inside a string or backticks in documentation.)
dart_pattern='(^|[^/`"'"'"'])//[[:space:]]*(ignore(_for_file)?:.*consolarr_|nosemgrep)'
yaml_pattern='^[^#]*consolarr_(no_ui_string|bad_certificate_callback|no_print)|#[[:space:]]*nosemgrep'

hits=$(
  {
    git grep -n -I -E "$dart_pattern" -- '*.dart' || true
    git grep -n -I -E "$yaml_pattern" -- '*.yaml' '*.yml' || true
  } | sort -u
)

status=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file=${hit%%:*}
  # Which rules does this line mention? `nosemgrep` counts as its own rule.
  rules=$(printf '%s\n' "$hit" | cut -d: -f3- | grep -o -E 'consolarr_[a-z_]+|nosemgrep' | sort -u || true)
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
