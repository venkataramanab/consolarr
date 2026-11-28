#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: dry_run.sh <work-dir>
#
# Exercises the whole release signing path with a THROWAWAY keystore generated
# at runtime (never committed): negative tests, then prepare_signing.sh,
# build_release.sh, verify_signature.sh, checksums and cleanup_signing.sh, in
# the order release.yml runs them. Prints digests only. Run from the repository
# root with flutter, keytool and apksigner (APKSIGNER) available.
set -euo pipefail

work="$(cd "${1:?usage: dry_run.sh <work-dir>}" && pwd)"
apksigner="${APKSIGNER:?set APKSIGNER to the apksigner path}"
tag="v0.0.0-dryrun"
apps=(apps/consolarr/android apps/consolarr_play/android)
version="$(bash tools/release/check_version.sh "v$(grep -E '^version:' apps/consolarr/pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9.]+).*/\1/')" apps/consolarr/pubspec.yaml apps/consolarr_play/pubspec.yaml)"
echo "== check_version: accepts the matching tag (${version})"

expect_fail() {
  local what="$1"
  shift
  if "$@" >"$work/neg.log" 2>&1; then
    echo "FAIL: expected failure: ${what}"
    exit 1
  fi
  echo "ok: refused: ${what}"
}

echo "== negative tests"
expect_fail "tag that is not vX.Y.Z" bash tools/release/check_version.sh v1.2.3-rc1 apps/consolarr/pubspec.yaml
expect_fail "tag that differs from the pubspec" bash tools/release/check_version.sh v99.0.0 apps/consolarr/pubspec.yaml
expect_fail "missing secrets" env -u KEYSTORE_BASE64 -u KEYSTORE_PASSWORD -u KEY_ALIAS -u KEY_PASSWORD \
  bash tools/release/prepare_signing.sh "$work/neg-signing" "${apps[0]}"
grep -q "KEYSTORE_BASE64 is empty" "$work/neg.log" && echo "ok: message names the missing secret"
[ ! -e "${apps[0]}/key.properties" ] || { echo "FAIL: key.properties written without secrets"; exit 1; }
expect_fail "invalid base64 keystore" env KEYSTORE_BASE64='!!!' KEYSTORE_PASSWORD=x KEY_ALIAS=x KEY_PASSWORD=x \
  bash tools/release/prepare_signing.sh "$work/neg-signing" "${apps[0]}"

echo "== generate throwaway keystore"
# Random passwords containing a backslash, to prove key.properties escaping.
pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"'\x'
keytool -genkeypair -keystore "$work/dry.p12" -storetype PKCS12 \
  -alias dryrun -keyalg RSA -keysize 2048 -validity 2 -dname "CN=Consolarr dry run" \
  -storepass "$pw" -keypass "$pw" 2>/dev/null
export KEYSTORE_BASE64
KEYSTORE_BASE64="$(base64 -w0 "$work/dry.p12")"
export KEYSTORE_PASSWORD="$pw" KEY_PASSWORD="$pw" KEY_ALIAS=dryrun
rm -f "$work/dry.p12"

# Never leave signing material behind, even when a step fails.
trap 'bash tools/release/cleanup_signing.sh "$work/signing" "${apps[@]}" >/dev/null' EXIT

echo "== prepare_signing"
bash tools/release/prepare_signing.sh "$work/signing" "${apps[@]}"
stat -c '%a %n' "$work/signing/release.jks" "${apps[0]}/key.properties" "${apps[1]}/key.properties"

echo "== build_release"
bash tools/release/build_release.sh "$tag" "$work/release" "$work/debug-info"

echo "== verify_signature + checksums"
(
  cd "$work/release"
  APKSIGNER="$apksigner" bash "$OLDPWD/tools/release/verify_signature.sh" SIGNING-CERT-SHA256.txt ./*.apk
  sha256sum -- ./*.apk | sed 's|  \./|  |' > SHA256SUMS.txt
  cat SHA256SUMS.txt
  sha256sum -c SHA256SUMS.txt
)

echo "== verify_signature rejects a different certificate and a debug certificate"
other="$work/other.p12"
for dn in "CN=Someone Else" "CN=Android Debug,O=Android,C=US"; do
  keytool -genkeypair -keystore "$other" -storetype PKCS12 -alias k -keyalg RSA -keysize 2048 \
    -validity 2 -dname "$dn" -storepass changeit -keypass changeit 2>/dev/null
  first="$(ls "$work"/release/*.apk | head -n1)"
  cp "$first" "$work/resigned.apk"
  "$apksigner" sign --ks "$other" --ks-pass pass:changeit --key-pass pass:changeit "$work/resigned.apk"
  rm -f "$other"
  if [ "$dn" = "CN=Someone Else" ]; then
    expect_fail "mixed signing certificates" env APKSIGNER="$apksigner" \
      bash tools/release/verify_signature.sh "$work/neg.txt" "$work/resigned.apk" "$work"/release/*.apk
  else
    expect_fail "Android debug certificate" env APKSIGNER="$apksigner" \
      bash tools/release/verify_signature.sh "$work/neg.txt" "$work/resigned.apk"
  fi
done
rm -f "$work/resigned.apk"

echo "== no debug-info in the release files"
if ls "$work/release" | grep -qiE 'symbols|debug-info'; then echo "FAIL: symbols staged"; exit 1; fi
ls "$work/debug-info"

echo "== cleanup_signing"
bash tools/release/cleanup_signing.sh "$work/signing" "${apps[@]}"
for f in "$work/signing/release.jks" "${apps[0]}/key.properties" "${apps[1]}/key.properties"; do
  [ ! -e "$f" ] || { echo "FAIL: ${f} still exists"; exit 1; }
done
echo "Dry run complete. Certificate SHA-256: $(cat "$work/release/SIGNING-CERT-SHA256.txt")"
