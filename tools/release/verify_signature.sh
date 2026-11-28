#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: verify_signature.sh <out-file> <apk>...
#
# Verifies each APK's signature with apksigner (from PATH, or APKSIGNER) and
# checks that all APKs are signed by the same certificate, which must not be an
# Android debug certificate. Prints and writes ONLY the certificate SHA-256
# digest, never any other certificate or key material.
set -euo pipefail

out="${1:?usage: verify_signature.sh <out-file> <apk>...}"
shift
[ "$#" -ge 1 ] || { echo "No APKs given." >&2; exit 2; }
apksigner="${APKSIGNER:-apksigner}"

digest=""
for apk in "$@"; do
  info="$("$apksigner" verify --print-certs "$apk")"
  if [ "$(printf '%s\n' "$info" | grep -c 'certificate SHA-256 digest:')" -ne 1 ]; then
    echo "::error::${apk} must have exactly one signer." >&2
    exit 1
  fi
  if printf '%s\n' "$info" | grep -q 'certificate DN:.*Android Debug'; then
    echo "::error::${apk} is signed with an Android debug certificate." >&2
    exit 1
  fi
  d="$(printf '%s\n' "$info" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  if ! printf '%s' "$d" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "::error::Could not read a certificate digest for ${apk}." >&2
    exit 1
  fi
  if [ -n "$digest" ] && [ "$d" != "$digest" ]; then
    echo "::error::APKs are not all signed by the same certificate." >&2
    exit 1
  fi
  digest="$d"
  echo "Signature verified: $(basename "$apk")"
done

echo "Certificate SHA-256: ${digest}"
printf '%s\n' "$digest" > "$out"
