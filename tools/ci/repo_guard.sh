#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Repo guard:
#  1. fails if keystore / credential-looking files are committed (or sit
#     untracked and un-ignored) outside the explicit allowlist in
#     tools/ci/forbidden_files_allowlist.txt;
#  2. fails if any tracked file lives under a `build/` directory (build output
#     is excluded from nothing but the root, apps/*, packages/* and tools/*
#     `build/` directories, so a source file hidden in a `lib/build/` folder
#     would otherwise be compiled but could not be hidden from scanners: it
#     must simply not exist);
#  3. fails if any tracked/unignored *.g.dart or *.freezed.dart file is not in
#     tools/ci/generated_files_allowlist.txt (generated code is committed only
#     deliberately: the analyzer no longer excludes it, but a padded generated
#     file was the vehicle for a scanner bypass);
#  4. fails if any tracked/unignored .dart file exceeds 512 KB and is not in
#     tools/ci/large_files_allowlist.txt (Semgrep and other scanners have size
#     limits; no legitimate hand-written source is that big);
#  5. fails if any term from $CLEANROOM_TERMS (newline-separated, supplied by
#     the CLEANROOM_TERMS repository *secret*) appears in file contents or
#     paths. Skips cleanly when the secret is unavailable (pull requests from
#     forks never receive secrets).
#
# The terms, and the files or lines they match, are NEVER printed: a term hit
# produces a count only. GitHub masks the secret in logs, but a masked file
# path would still reveal where a hit is, so counts are all we emit.
#
# Certificate fixtures: tests must generate certificates and keys at test time
# into an ignored directory (`**/test/.generated/`, see .gitignore). Committed
# `.pem`/`.key`/`.p12`/... files fail this guard.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
set +x # never trace: tracing would print the terms

fail=0

# --- 1. forbidden files ------------------------------------------------------
forbidden_regex='(^|/)(key\.properties|local\.properties|google-services\.json|GoogleService-Info\.plist|credentials\.json|id_rsa|id_ed25519|\.env(\..*)?|dart_defines[^/]*\.json)$|\.(jks|keystore|p12|pfx|p8|pem|key|ppk|gpg|asc|crt|cer|der)$|(^|/)service[-_]account[^/]*\.json$'
allowlist_file=tools/ci/forbidden_files_allowlist.txt

allowed_paths=$(mktemp)
terms_file=$(mktemp)
trap 'rm -f "$allowed_paths" "$terms_file"' EXIT
{
  echo 'dart_defines.example.json'
  [ -f "$allowlist_file" ] && sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$allowlist_file"
} > "$allowed_paths"

# Tracked files and untracked-but-not-ignored files (ignored directories such
# as the generated-fixture directory are skipped by --exclude-standard).
hits=$(git ls-files --cached --others --exclude-standard \
  | grep -E "$forbidden_regex" \
  | grep -Fxv -f "$allowed_paths" || true)

printf '%s\n' "${CLEANROOM_TERMS:-}" | sed -e 's/\r$//' -e '/^[[:space:]]*$/d' > "$terms_file"
# Never echo the name of a file whose *path* contains a protected term.
if [ -n "$hits" ] && [ -s "$terms_file" ]; then
  hits=$(printf '%s\n' "$hits" | grep -i -v -F -f "$terms_file" || true)
fi
if [ -n "$hits" ]; then
  echo "::error::Forbidden credential/keystore/certificate files are committed:"
  echo "$hits"
  echo "Generate certificates at test time into **/test/.generated/ instead."
  fail=1
fi

# --- 2. tracked files under build/ ------------------------------------------
build_hits=$(git ls-files --cached | grep -E '(^|/)build/' || true)
if [ -n "$build_hits" ]; then
  echo "::error::Tracked files under a build/ directory (build output is git-ignored and never scanned; do not force-add):"
  printf '%s\n' "$build_hits"
  fail=1
fi

# --- 3./4. generated and oversized Dart files -------------------------------
read_allowlist() { # read_allowlist <file>: exact repo-relative paths
  [ -f "$1" ] && sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1" || true
}
dart_files=$(git ls-files --cached --others --exclude-standard | grep -E '\.dart$' || true)

gen_allowed=$(mktemp)
big_allowed=$(mktemp)
trap 'rm -f "$allowed_paths" "$terms_file" "$gen_allowed" "$big_allowed"' EXIT
read_allowlist tools/ci/generated_files_allowlist.txt > "$gen_allowed"
read_allowlist tools/ci/large_files_allowlist.txt > "$big_allowed"

gen_hits=$(printf '%s\n' "$dart_files" | grep -iE '\.(g|freezed)\.dart$' | grep -Fxv -f "$gen_allowed" || true)
if [ -n "$gen_hits" ]; then
  echo "::error::Generated Dart files (*.g.dart, *.freezed.dart) are committed outside tools/ci/generated_files_allowlist.txt:"
  printf '%s\n' "$gen_hits"
  fail=1
fi

max_dart_bytes=524288
big_hits=""
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  size=$(wc -c < "$f" | tr -d ' ')
  if [ "$size" -gt "$max_dart_bytes" ]; then
    big_hits="${big_hits}${f} (${size} bytes)"$'\n'
  fi
done < <(printf '%s\n' "$dart_files" | grep -Fxv -f "$big_allowed" || true)
if [ -n "$big_hits" ]; then
  echo "::error::Dart files larger than 512 KB (scanner size limits; split or allowlist in tools/ci/large_files_allowlist.txt):"
  printf '%s' "$big_hits"
  fail=1
fi

# --- 5. clean-room terms -----------------------------------------------------
if [ ! -s "$terms_file" ]; then
  echo "CLEANROOM_TERMS secret not available (fork pull request or not configured): clean-room term check skipped."
else
  # Register every line as a mask in case the runner only masks the whole value.
  while IFS= read -r term; do
    printf '::add-mask::%s\n' "$term"
  done < "$terms_file"

  count=$(wc -l < "$terms_file" | tr -d ' ')
  echo "Checking repository against $count protected term(s) (terms and matches are not printed)."

  content_hits=$(git grep --untracked -I -i -l -F -f "$terms_file" -- . ':!.git' 2>/dev/null | wc -l | tr -d ' ' || true)
  if [ "${content_hits:-0}" -gt 0 ]; then
    echo "::error::Protected terms appear in the content of ${content_hits} file(s) (paths not printed)."
    fail=1
  fi

  path_hits=$(git ls-files --cached --others --exclude-standard | grep -i -c -F -f "$terms_file" || true)
  if [ "${path_hits:-0}" -gt 0 ]; then
    echo "::error::Protected terms appear in ${path_hits} file path(s) (paths not printed)."
    fail=1
  fi

  # Commit messages are public too.
  msg_hits=$(git log --all --format=%B 2>/dev/null | grep -i -c -F -f "$terms_file" || true)
  if [ "${msg_hits:-0}" -gt 0 ]; then
    echo "::error::Protected terms appear in ${msg_hits} commit message line(s) (not printed)."
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Repo guard passed."
