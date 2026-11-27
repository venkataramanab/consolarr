#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Proves the consolarr_lints analyzer plugin is loaded: analyses a file with
# deliberate violations and expects each rule to report.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

target=apps/consolarr/lib/lint_canary_tmp.dart
cp tools/ci/canary/violations.dart.txt "$target"
trap 'rm -f "$target"' EXIT

output=$(dart analyze apps/consolarr 2>&1 || true)
status=0
for rule in consolarr_no_ui_string consolarr_bad_certificate_callback consolarr_no_print; do
  if echo "$output" | grep -q "$rule"; then
    echo "ok: $rule reported"
  else
    echo "::error::$rule did not report on the canary; is the analyzer plugin loaded?"
    status=1
  fi
done
[ "$status" -eq 0 ] || echo "$output"
exit "$status"
