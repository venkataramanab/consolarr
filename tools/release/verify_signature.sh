#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: verify_signature.sh <out-file> [--] <apk>...
#
# Verifies each APK's signature with apksigner (from PATH, or APKSIGNER),
# requires the v2 and v3 signature schemes, and checks that all APKs are signed
# by the same certificate, which must not be an Android debug certificate.
# If EXPECTED_CERT_SHA256 is set (the pinned release certificate, any case,
# with or without colons) every APK must match it; if it is empty a warning is
# emitted and the check is skipped (first release only).
# Prints and writes ONLY the certificate SHA-256 digest (lowercase hex, no
# colons), never any other certificate or key material.
set -euo pipefail

out="${1:?usage: verify_signature.sh <out-file> [--] <apk>...}"
shift
if [ "${1:-}" = "--" ]; then shift; fi
[ "$#" -ge 1 ] || { echo "No APKs given." >&2; exit 2; }
apksigner="${APKSIGNER:-apksigner}"

expected="$(printf '%s' "${EXPECTED_CERT_SHA256:-}" | tr -d ': \t\r\n' | tr 'A-F' 'a-f')"
if [ -z "$expected" ]; then
  echo "::warning::EXPECTED_CERT_SHA256 (repo variable RELEASE_CERT_SHA256) is not set, so the signing certificate is not pinned. Set it now (see docs/releasing.md)."
elif ! printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "::error::The pinned certificate digest is not 64 hex digits." >&2
  exit 1
fi

digest=""
for apk in "$@"; do
  info="$("$apksigner" verify --verbose --print-certs --min-sdk-version 26 "$apk")"
  for scheme in 'v2 scheme (APK Signature Scheme v2)' 'v3 scheme (APK Signature Scheme v3)'; do
    if ! printf '%s\n' "$info" | grep -qFx "Verified using ${scheme}: true"; then
      echo "::error::${apk} is not verified with the ${scheme%% *} signature scheme." >&2
      exit 1
    fi
  done
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
  if [ -n "$expected" ] && [ "$d" != "$expected" ]; then
    echo "::error::${apk} is not signed with the pinned release certificate." >&2
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
