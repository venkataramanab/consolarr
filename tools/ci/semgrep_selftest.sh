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

git init -q . && git add -A # semgrep only scans files that git knows about
semgrep scan --config "$repo/tools/semgrep/consolarr.yml" --disable-nosem --disable-version-check \
  --metrics=off --json --quiet apps packages > out.json || true
python3 -I - <<'PY'
import json, sys
hits = {(r["path"], r["check_id"].split(".")[-1]) for r in json.load(open("out.json"))["results"]}
want = {
    ("apps/consolarr/lib/services/nosem_short.dart", "consolarr-bad-certificate-callback"),
    ("packages/probe/lib/nosem_block.dart", "consolarr-bad-certificate-callback"),
    ("apps/consolarr/lib/build/hidden.dart", "consolarr-bad-certificate-callback"),
    ("apps/consolarr/lib/services/alias.dart", "consolarr-pin-confirmation-construction"),
}
missing = want - hits
# Real build output (apps/*/build) stays excluded; the confirmation UI may construct.
unexpected = {h for h in hits if h[0] in ("apps/consolarr/build/generated.dart", "apps/consolarr/lib/features/ok.dart")}
alias_hits = [h for h in hits if h[0].endswith("alias.dart")]
if missing or unexpected:
    print("::error::semgrep self-test: missing=%s unexpected=%s" % (sorted(missing), sorted(unexpected)))
    sys.exit(1)
print("semgrep self-test passed (%d findings)" % len(hits))
PY
