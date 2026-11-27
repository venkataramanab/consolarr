#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Proves the consolarr_lints analyzer plugin is loaded: analyses a file with
# deliberate violations and expects each rule to report.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

target=apps/consolarr/lib/lint_canary_tmp.dart
build_target=apps/consolarr/lib/build/lint_canary_tmp.dart
cp tools/ci/canary/violations.dart.txt "$target"
mkdir -p "$(dirname "$build_target")"
cp tools/ci/canary/violations.dart.txt "$build_target"
trap 'rm -f "$target" "$build_target"; rmdir "$(dirname "$build_target")" 2>/dev/null || true' EXIT

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
# A source directory named build/ is compiled into the app, so it must be
# analyzed (only real build output directories are excluded).
if echo "$output" | grep -q "lib/build/lint_canary_tmp.dart.*consolarr_bad_certificate_callback"; then
  echo "ok: lib/build/ is analyzed"
else
  echo "::error::apps/consolarr/lib/build/ is not analyzed; check the analyzer excludes in analysis_options.yaml."
  status=1
fi
[ "$status" -eq 0 ] || echo "$output"
exit "$status"
