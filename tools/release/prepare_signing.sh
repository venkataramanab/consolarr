#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: prepare_signing.sh <key-dir> <app-android-dir>...
#
# Decodes the release keystore and writes key.properties for each app.
# Reads KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD from the
# environment only (never from arguments, so `ps` cannot show them) and never
# prints them. Fails fast, with a clear message, if any of them is missing.
# Files are created with mode 600 under a 077 umask.
set -euo pipefail
umask 077

dir="${1:?usage: prepare_signing.sh <key-dir> <app-android-dir>...}"
shift
[ "$#" -ge 1 ] || { echo "::error::No app android directories given." >&2; exit 2; }

missing=0
for name in KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  if [ -z "${!name:-}" ]; then
    echo "::error::Secret ${name} is empty or not set. Add it as an environment secret of the 'release' environment (see docs/releasing.md)." >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

# key.properties is a Java properties file: a backslash is an escape character
# and a line break would end the value. Reject the latter, escape the former.
for name in KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  case "${!name}" in
    *$'\n'* | *$'\r'*)
      echo "::error::Secret ${name} contains a line break, which key.properties cannot hold." >&2
      exit 1
      ;;
  esac
done
esc() { printf '%s' "${1//\\/\\\\}"; }

mkdir -p "$dir"
chmod 700 "$dir"
store="$dir/release.jks"
printf '%s' "$KEYSTORE_BASE64" | base64 -d > "$store" || {
  echo "::error::KEYSTORE_BASE64 is not valid base64." >&2
  rm -f "$store"
  exit 1
}
chmod 600 "$store"
[ -s "$store" ] || { echo "::error::Decoded keystore is empty." >&2; exit 1; }

for app in "$@"; do
  props="$app/key.properties"
  {
    printf 'storeFile=%s\n' "$(esc "$store")"
    printf 'storePassword=%s\n' "$(esc "$KEYSTORE_PASSWORD")"
    printf 'keyAlias=%s\n' "$(esc "$KEY_ALIAS")"
    printf 'keyPassword=%s\n' "$(esc "$KEY_PASSWORD")"
  } > "$props"
  chmod 600 "$props"
  echo "Wrote ${props} (mode 600)."
done
echo "Keystore decoded to ${store} (mode 600)."
