#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-tests for the CI guard scripts: each guard must pass clean input and
# fail planted violations, so a guard that silently stopped working is caught.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
cd "$repo"

fail() { echo "::error::selftest: $*"; exit 1; }

echo "== merged-manifest checker"
python3 tools/ci/check_merged_manifest.py --self-test

echo "== licence detector"
dart run tools/ci/check_licenses_selftest.dart

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

new_repo() { # copies the guard scripts into a fresh git repo
  local d=$1
  mkdir -p "$d/tools/ci" && cp tools/ci/*.sh tools/ci/*.txt "$d/tools/ci/"
  git -C "$d" init -q .
  git -C "$d" config user.email ci@example.invalid
  git -C "$d" config user.name ci
  echo '// clean' > "$d/ok.dart"
  git -C "$d" add -A && git -C "$d" commit -qm init
}

echo "== suppression guard"
s="$scratch/supp"; new_repo "$s"
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null || fail "clean repo should pass"
plant() { printf '%s\n' "$2" > "$s/$1"; git -C "$s" add -A; }
plant a.dart '// ignore: consolarr_bad_certificate_callback -- nope'
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "cert-rule ignore must fail"
plant a.dart 'var x = 1; // nosemgrep'
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "nosemgrep must fail"
plant a.dart '// ignore_for_file: consolarr_no_print'
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "ignore_for_file must fail"
rm "$s/a.dart"
printf 'analyzer:\n  errors:\n    consolarr_no_print: ignore\n' > "$s/analysis_options.yaml"; git -C "$s" add -A
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "analysis_options override must fail"

echo "== repo guard"
g="$scratch/guard"; new_repo "$g"
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null) || fail "clean repo should pass"
(cd "$g" && CLEANROOM_TERMS='' bash tools/ci/repo_guard.sh | grep -q skipped) || fail "empty terms must skip cleanly"
echo "contains zz-protected-term here" > "$g/doc.txt"; git -C "$g" add -A
out=$(cd "$g" && CLEANROOM_TERMS=$'zz-protected-term\n' bash tools/ci/repo_guard.sh 2>&1) && fail "term hit must fail"
echo "$out" | grep -q 'doc.txt' && fail "term hit must not print the file path"
# (the ::add-mask:: workflow command is consumed by the runner, never shown)
echo "$out" | grep -v '^::add-mask::' | grep -q 'zz-protected-term' && fail "term must not be printed"
git -C "$g" rm -qf doc.txt
echo x > "$g/server.pem"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "committed .pem must fail"
git -C "$g" rm -qf server.pem
mkdir -p "$g/pkg/test/.generated"; echo "pkg/test/.generated/" > "$g/.gitignore"
echo x > "$g/pkg/test/.generated/fixture.pem"
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null) || fail "test-time generated certs in an ignored dir must pass"

echo "All CI guard self-tests passed."
