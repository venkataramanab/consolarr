#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Repo guard:
#  1. fails if keystore / credential-looking files are present in the repo;
#  2. fails if any term from $CLEANROOM_TERMS (newline-separated, supplied by
#     the CLEANROOM_TERMS repository *variable*) appears in file contents or
#     paths. Skips cleanly when the variable is empty.
#
# The terms themselves are NEVER printed: only file paths (for content hits)
# or counts (for path hits).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
set +x # never trace: tracing would print the terms

fail=0

# --- 1. forbidden files ------------------------------------------------------
forbidden_regex='(^|/)(key\.properties|local\.properties|google-services\.json|GoogleService-Info\.plist|credentials\.json|id_rsa|id_ed25519|\.env(\..*)?|dart_defines[^/]*\.json)$|\.(jks|keystore|p12|pfx|p8|pem|key|ppk|gpg|asc)$|(^|/)service[-_]account[^/]*\.json$'
allowed_regex='(^|/)dart_defines\.example\.json$'

hits=$(git ls-files --cached --others --exclude-standard \
  | grep -E "$forbidden_regex" | grep -Ev "$allowed_regex" || true)
if [ -n "$hits" ]; then
  echo "::error::Forbidden credential/keystore files present:"
  echo "$hits"
  fail=1
fi

# --- 2. clean-room terms -----------------------------------------------------
terms_file=$(mktemp)
trap 'rm -f "$terms_file"' EXIT
printf '%s\n' "${CLEANROOM_TERMS:-}" | sed -e 's/\r$//' -e '/^[[:space:]]*$/d' > "$terms_file"

if [ ! -s "$terms_file" ]; then
  echo "CLEANROOM_TERMS is empty: clean-room term check skipped."
else
  count=$(wc -l < "$terms_file" | tr -d ' ')
  echo "Checking repository against $count protected term(s) (terms are not printed)."

  content_hits=$(git grep --untracked -I -i -l -F -f "$terms_file" -- . ':!.git' 2>/dev/null || true)
  if [ -n "$content_hits" ]; then
    echo "::error::A protected term appears in the content of these files:"
    echo "$content_hits"
    fail=1
  fi

  path_hits=$(git ls-files --cached --others --exclude-standard | grep -i -c -F -f "$terms_file" || true)
  if [ "${path_hits:-0}" -gt 0 ]; then
    echo "::error::A protected term appears in $path_hits file path(s) (paths not printed)."
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Repo guard passed."
