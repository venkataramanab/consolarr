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

echo "== apk size gate"
apk="$scratch/app.apk"
truncate -s 10M "$apk"
out=$(bash tools/ci/check_apk_size.sh "$apk" 20 2>&1) || fail "10 MiB must pass a 20 MiB budget"
echo "$out" | grep -q '::warning::' && fail "10 MiB must not warn"
truncate -s 19M "$apk"
out=$(bash tools/ci/check_apk_size.sh "$apk" 20 2>&1) || fail "19 MiB must pass (with a warning)"
echo "$out" | grep -q '::warning::' || fail "19 MiB must warn at 90% of the budget"
truncate -s 21M "$apk"
bash tools/ci/check_apk_size.sh "$apk" 20 >/dev/null 2>&1 && fail "21 MiB must fail"

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
# Bypass probes (each must fail on its own, and in combination).
probe() { # probe <label> <content...>: planted file must be rejected
  local label=$1; shift
  plant a.dart "$(printf '%s\n' "$@")"
  bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "$label must fail"
  return 0
}
probe "ignore: type=lint" '// ignore: type=lint' 'var x = 1;'
probe "ignore_for_file: type=lint" '// ignore_for_file: type=lint'
probe "ignore_for_file: type = lint (spaces)" '//ignore_for_file:   type = lint'
probe "ignore list containing type=lint" 'var x = 1; // ignore: unused_local_variable, type=lint'
probe "short-form nosem" 'var x = 1; // nosem'
probe "nosem with rule id" 'var x = 1; // nosem: consolarr-bad-certificate-callback'
probe "block-comment nosemgrep" 'var x = 1; /* nosemgrep */'
probe "block-comment nosem" 'var x = 1; /* nosem */'
probe "doc-comment nosem" '/// nosem'
probe "comment after a string literal" "var x = 'a'; // nosemgrep"
probe "comment after a double-quoted string" 'var x = "a"; // ignore: consolarr_no_print'
probe "ignore after a string literal" "var x = 'a'; // ignore_for_file: type=lint"
probe "combined bypass" '// ignore: type=lint' 'HttpClient()..badCertificateCallback = (_, __, ___) => true; // nosem'
plant a.dart '// ignore: unused_local_variable
var nosemantics = 1; // not a suppression'
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 || fail "unrelated words/ignores must pass"
# The shared test harness is library code: no analyzer suppression at all,
# whatever the rule (a non-project ignore used to pass unnoticed).
rm "$s/a.dart"
mkdir -p "$s/packages/test_harness/lib/src" "$s/packages/test_harness/test"
hp=packages/test_harness/lib/src/x.dart
printf '%s\n' '// ignore: invalid_use_of_visible_for_testing_member' 'class X {}' > "$s/$hp"; git -C "$s" add -A
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "test_harness lib ignore must fail"
printf '%s\n' 'class X {}  // ignore_for_file: unused_element' > "$s/$hp"; git -C "$s" add -A
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 && fail "test_harness lib ignore_for_file must fail"
printf '%s\n' 'class X {}' > "$s/$hp"
# ... but the same form elsewhere (and in the harness's own tests) stays allowed.
printf '%s\n' '// ignore: unused_local_variable' 'var y = 1;' > "$s/packages/test_harness/test/x_test.dart"
printf '%s\n' '// ignore: unused_local_variable' 'var y = 1;' > "$s/b.dart"
git -C "$s" add -A
bash "$s/tools/ci/check_suppressions.sh" "$s" >/dev/null 2>&1 || fail "harness test and other ignores must still pass"
rm -r "$s/packages" "$s/b.dart"; git -C "$s" add -A
rm -f "$s/a.dart"
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

mkdir -p "$g/apps/x/lib/build"; echo '// x' > "$g/apps/x/lib/build/x.dart"; git -C "$g" add -f apps
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked file under lib/build/ must fail"
git -C "$g" rm -qrf apps
mkdir -p "$g/build"; echo '// x' > "$g/build/x.dart"; git -C "$g" add -f build
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked root build/ file must fail"
git -C "$g" rm -qrf build
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null) || fail "repo without build/ files must pass"

# Codegen output (localizations, event catalog) must never be tracked.
mkdir -p "$g/packages/l10n/lib/arb"; echo '{}' > "$g/packages/l10n/lib/arb/app_en.arb"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked l10n codegen output must fail"
git -C "$g" rm -qrf packages
mkdir -p "$g/packages/observability/lib/src/events"; echo '// x' > "$g/packages/observability/lib/src/events/catalog.dart"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked event catalog must fail"
git -C "$g" rm -qrf packages
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null) || fail "repo without codegen output must pass"

# Generated and oversized Dart files (padded-file scanner bypass).
echo '// x' > "$g/a.freezed.dart"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked *.freezed.dart must fail"
git -C "$g" rm -qf a.freezed.dart
mkdir -p "$g/lib"; echo '// x' > "$g/lib/m.g.dart"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked *.g.dart must fail"
echo 'lib/m.g.dart' >> "$g/tools/ci/generated_files_allowlist.txt"
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) || fail "allowlisted *.g.dart must pass"
git -C "$g" rm -qf lib/m.g.dart; git -C "$g" checkout -q -- tools/ci/generated_files_allowlist.txt 2>/dev/null || true
mkdir -p "$g/lib"
# Padded generated file (> 1 MB, the Semgrep default limit): caught by the
# generated-file rule and, independently, by the size rule.
{ echo 'HttpClient()..badCertificateCallback = (_, __, ___) => true;'; python3 -I -c "print('// ' + 'x' * 1100000)"; } > "$g/lib/p.freezed.dart"
git -C "$g" add -A
out=$(cd "$g" && bash tools/ci/repo_guard.sh 2>&1) && fail "padded *.freezed.dart must fail"
echo "$out" | grep -q 'larger than 512 KB' || fail "padded *.freezed.dart must trip the size rule"
echo 'lib/p.freezed.dart' >> "$g/tools/ci/generated_files_allowlist.txt"
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "allowlisting only the generated rule must not hide the size rule"
git -C "$g" rm -qf lib/p.freezed.dart
# Oversized plain .dart file.
mkdir -p "$g/lib"
python3 -I -c "print('// ' + 'x' * 600000)" > "$g/lib/big.dart"; git -C "$g" add -A
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) && fail "tracked .dart over 512 KB must fail"
echo 'lib/big.dart' >> "$g/tools/ci/large_files_allowlist.txt"
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null 2>&1) || fail "allowlisted large .dart must pass"
git -C "$g" rm -qf lib/big.dart
git -C "$g" checkout -q -- tools/ci 2>/dev/null || true
(cd "$g" && bash tools/ci/repo_guard.sh >/dev/null) || fail "repo guard should pass again after cleanup"

echo "== analysis_options guard"
a="$scratch/ao"; new_repo "$a"
mkdir -p "$a/apps/app" "$a/packages/p" "$a/tools/consolarr_lints"
printf 'plugins:\n  consolarr_lints:\n    path: tools/consolarr_lints\n' > "$a/analysis_options.yaml"
printf 'include: ../../analysis_options.yaml\n' > "$a/apps/app/analysis_options.yaml"
printf 'include: package:lints/recommended.yaml\n' > "$a/tools/consolarr_lints/analysis_options.yaml"
git -C "$a" add -A
bash "$a/tools/ci/check_analysis_options.sh" "$a" >/dev/null || fail "nested file including the root must pass"
printf 'linter:\n  rules:\n    avoid_print: false\n' > "$a/packages/p/analysis_options.yaml"; git -C "$a" add -A
bash "$a/tools/ci/check_analysis_options.sh" "$a" >/dev/null 2>&1 && fail "nested file without include must fail"
printf 'include: package:lints/recommended.yaml\n' > "$a/packages/p/analysis_options.yaml"; git -C "$a" add -A
bash "$a/tools/ci/check_analysis_options.sh" "$a" >/dev/null 2>&1 && fail "nested file including something else must fail"
printf 'include: ../../apps/app/analysis_options.yaml\n' > "$a/packages/p/analysis_options.yaml"; git -C "$a" add -A
bash "$a/tools/ci/check_analysis_options.sh" "$a" >/dev/null 2>&1 && fail "include chain not reaching the root directly must fail"
printf 'include: ../../analysis_options.yaml\n' > "$a/packages/p/analysis_options.yaml"
printf 'include: package:lints/recommended.yaml\n' > "$a/apps/analysis_options.yaml"; git -C "$a" add -A
bash "$a/tools/ci/check_analysis_options.sh" "$a" >/dev/null 2>&1 && fail "only the plugin package itself is exempt"

echo "All CI guard self-tests passed."
