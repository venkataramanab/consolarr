#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Proves the Semgrep rules cannot be sidestepped by the known tricks: `nosem`
# comments (scanning uses --disable-nosem), a typedef/prefix/tear-off alias of
# UserPinConfirmation, and a source directory named `build/`. Requires semgrep
# on PATH. Run from anywhere inside the repository.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
cp "$repo/.semgrepignore" .

w() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

w apps/consolarr/lib/services/nosem_short.dart <<'DART'
void f(dynamic c) { c.badCertificateCallback = (_, __, ___) => true; } // nosem
DART
w packages/probe/lib/nosem_block.dart <<'DART'
void f(dynamic c) { /* nosemgrep */ c.badCertificateCallback = (_, __, ___) => true; }
DART
w apps/consolarr/lib/build/hidden.dart <<'DART'
void f(dynamic c) { c.badCertificateCallback = (_, __, ___) => true; }
DART
w apps/consolarr/lib/services/alias.dart <<'DART'
import 'package:security/security.dart' as s;
typedef C = s.UserPinConfirmation;
final a = C.userAccepted;
final b = s.UserPinConfirmation . userAccepted;
DART
w apps/consolarr/lib/features/ok.dart <<'DART'
final ok = UserPinConfirmation.userAccepted;
DART
w apps/consolarr/build/generated.dart <<'DART'
void f(dynamic c) { c.badCertificateCallback = (_, __, ___) => true; }
DART

# Padded (> 1 MB) generated-looking file and an oversized plain file: the scan
# must have no size limit and must not skip them.
pad() { python3 -I -c "print('// ' + 'x' * 1100000)"; }
{ echo 'void f(dynamic c) { c.badCertificateCallback = (_, __, ___) => true; }'; pad; } \
  > apps/consolarr/lib/padded.freezed.dart
{ echo 'void f(dynamic c) { c.badCertificateCallback = (_, __, ___) => true; }'; pad; } \
  > packages/probe/lib/padded_plain.dart
w packages/probe/lib/roots.dart <<'DART'
void f(dynamic b) { SecurityContext(withTrustedRoots: b); SecurityContext(withTrustedRoots: !true); }
DART
w packages/probe/lib/roots_ok.dart <<'DART'
void f() { SecurityContext(withTrustedRoots: true); }
DART

git init -q . && git add -A # semgrep only scans files that git knows about
semgrep scan --verbose --max-target-bytes 0 --config "$repo/tools/semgrep/consolarr.yml" --disable-nosem --disable-version-check \
  --metrics=off --json --json-output=out.json apps packages >/dev/null 2>&1 || true
python3 -I - <<'PY'
import json, sys
hits = {(r["path"], r["check_id"].split(".")[-1]) for r in json.load(open("out.json"))["results"]}
want = {
    ("apps/consolarr/lib/services/nosem_short.dart", "consolarr-bad-certificate-callback"),
    ("packages/probe/lib/nosem_block.dart", "consolarr-bad-certificate-callback"),
    ("apps/consolarr/lib/build/hidden.dart", "consolarr-bad-certificate-callback"),
    ("apps/consolarr/lib/services/alias.dart", "consolarr-pin-confirmation-construction"),
    ("apps/consolarr/lib/padded.freezed.dart", "consolarr-bad-certificate-callback"),
    ("packages/probe/lib/padded_plain.dart", "consolarr-bad-certificate-callback"),
    ("packages/probe/lib/roots.dart", "consolarr-bad-certificate-callback"),
}
missing = want - hits
# Real build output (apps/*/build) stays excluded; the confirmation UI may construct.
unexpected = {h for h in hits if h[0] in ("apps/consolarr/build/generated.dart", "apps/consolarr/lib/features/ok.dart", "packages/probe/lib/roots_ok.dart")}
alias_hits = [h for h in hits if h[0].endswith("alias.dart")]
if missing or unexpected:
    print("::error::semgrep self-test: missing=%s unexpected=%s" % (sorted(missing), sorted(unexpected)))
    sys.exit(1)
print("semgrep self-test passed (%d findings)" % len(hits))
PY

# The skipped-file check must flag a size-limit skip (default 1 MB limit) and
# accept only .semgrepignore'd build output.
semgrep scan --config "$repo/tools/semgrep/consolarr.yml" --disable-nosem --disable-version-check \
  --metrics=off --verbose --json-output=default_limit.json apps packages >/dev/null 2>&1 || true
python3 -I "$repo/tools/ci/semgrep_skipped.py" default_limit.json >/dev/null 2>&1 \
  && { echo "::error::semgrep self-test: skipped-file check accepted a size-limit skip"; exit 1; }
python3 -I "$repo/tools/ci/semgrep_skipped.py" out.json >/dev/null \
  || { echo "::error::semgrep self-test: skipped-file check rejected a no-limit scan"; exit 1; }
# End to end: the real wrapper must fail on this tree (violations present).
SEMGREP_CONFIG="$repo/tools/semgrep/consolarr.yml" bash "$repo/tools/ci/semgrep_scan.sh" apps packages >/dev/null 2>&1 \
  && { echo "::error::semgrep self-test: semgrep_scan.sh passed a tree with violations"; exit 1; }
echo "semgrep skipped-file self-test passed"
