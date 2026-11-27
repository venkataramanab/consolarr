#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Proves gitleaks really scans with .gitleaks.toml: a freshly generated,
# token-shaped value (never committed) must be reported, and the allowlisted
# fake fixture key must not be.
set -uo pipefail
repo=$(git rev-parse --show-toplevel)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp "$repo/.gitleaks.toml" "$dir/.gitleaks.toml"

detected=1
for _ in 1 2 3 4 5; do
  token=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 36 || true)
  printf 'token = "ghp_%s"\n' "$token" > "$dir/planted.txt"
  if ! gitleaks dir --config "$dir/.gitleaks.toml" --no-banner --redact "$dir" >/dev/null 2>&1; then
    detected=0; break
  fi
done
if [ "$detected" -ne 0 ]; then
  echo "::error::gitleaks did not report a planted token: scanning is not working."
  exit 1
fi
rm -f "$dir/planted.txt"
printf 'api_key = "test-key-0000"\n' > "$dir/fixture.txt"
if ! gitleaks dir --config "$dir/.gitleaks.toml" --no-banner --redact "$dir" >/dev/null 2>&1; then
  echo "::error::the fake fixture key should be allowlisted."
  exit 1
fi
echo "gitleaks canary ok"
