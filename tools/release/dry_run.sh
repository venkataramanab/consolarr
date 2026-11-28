#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: dry_run.sh <work-dir>
#
# Exercises the whole release path with a THROWAWAY keystore generated at
# runtime (never committed): negative tests, then every stage of release.yml in
# its order. Each stage runs through `tools/release/stage.sh <stage>`, the exact
# command line release.yml uses; the script fails if release.yml calls anything
# else or a stage that is not run here. Prints digests only. Run from the repository
# root with flutter, keytool and apksigner (APKSIGNER) available.
set -euo pipefail

work="$(cd "${1:?usage: dry_run.sh <work-dir>}" && pwd)"
apksigner="${APKSIGNER:?set APKSIGNER to the apksigner path}"
tag="v0.0.0"
apps=(apps/consolarr/android apps/consolarr_play/android)
version="$(bash tools/release/check_version.sh "v$(grep -E '^version:' apps/consolarr/pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9.]+).*/\1/')" apps/consolarr/pubspec.yaml apps/consolarr_play/pubspec.yaml)"
echo "== check_version: accepts the matching tag (${version})"

stages_run=()
run_stage() {
  stages_run+=("$1")
  bash tools/release/stage.sh "$@"
}

# release.yml may only call `bash tools/release/stage.sh <stage>` (nothing else
# under tools/release, no extra arguments), and the dry run must run the same
# set of stages.
echo "== release.yml calls only the stages this script runs"
calls="$(grep -n 'tools/release/' .github/workflows/release.yml | grep -v '^[0-9]*:[[:space:]]*#' || true)"
bad="$(printf '%s\n' "$calls" | grep -v -E '^[0-9]+:[[:space:]]+run: bash tools/release/stage\.sh [a-z]+$' || true)"
if [ -n "$calls" ] && [ -n "$bad" ]; then
  echo "FAIL: release.yml has a tools/release call that is not a plain stage.sh stage:"
  echo "$bad"
  exit 1
fi
workflow_stages="$(printf '%s\n' "$calls" | sed -E 's/.*stage\.sh ([a-z]+)$/\1/' | sort -u | tr '\n' ' ')"
echo "release.yml stages: ${workflow_stages}"

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
for bad in 'v1.2.3-rc1' 'v1.2.3 ::notice::x' 'v1.2.3%0A::error::y' ''; do
  expect_fail "tag stage rejects an invalid tag" env TAG="$bad" GITHUB_REF="refs/tags/$bad" RUNNER_TEMP="$work" \
    bash tools/release/stage.sh tag
  if grep -qF -- "::notice::x" "$work/neg.log" || grep -qF -- "0A::error::y" "$work/neg.log"; then
    echo "FAIL: the raw tag was echoed"
    exit 1
  fi
done
echo "ok: the raw tag was never echoed"
expect_fail "build stage rejects an invalid tag" env TAG='v1.2' RUNNER_TEMP="$work" bash tools/release/stage.sh build
expect_fail "tag that differs from the pubspec" bash tools/release/check_version.sh v99.0.0 apps/consolarr/pubspec.yaml
expect_fail "missing secrets" env -u KEYSTORE_BASE64 -u KEYSTORE_PASSWORD -u KEY_ALIAS -u KEY_PASSWORD \
  RUNNER_TEMP="$work/neg" bash tools/release/stage.sh prepare
grep -q "KEYSTORE_BASE64 is empty" "$work/neg.log" && echo "ok: message names the missing secret"
[ ! -e "${apps[0]}/key.properties" ] || { echo "FAIL: key.properties written without secrets"; exit 1; }
expect_fail "invalid base64 keystore" env KEYSTORE_BASE64='!!!' KEYSTORE_PASSWORD=x KEY_ALIAS=x KEY_PASSWORD=x \
  RUNNER_TEMP="$work/neg" bash tools/release/stage.sh prepare
[ ! -e "${apps[1]}/key.properties" ] || { echo "FAIL: key.properties written"; exit 1; }
rm -rf "$work/neg"

echo "== stage tag (in a scratch repository with a local origin)"
root="$(pwd)"
rel_version="$(printf '%s' "$version")"
repo="$work/tagrepo"
rm -rf "$repo" "$work/tagorigin.git"
mkdir -p "$repo/apps/consolarr" "$repo/apps/consolarr_play"
cp apps/consolarr/pubspec.yaml "$repo/apps/consolarr/"
cp apps/consolarr_play/pubspec.yaml "$repo/apps/consolarr_play/"
gitq() { git -C "$repo" -c user.name=dry -c user.email=dry@example.invalid "$@"; }
git init -q --bare "$work/tagorigin.git"
git init -q -b main "$repo"
gitq add . && gitq commit -q -m base
gitq remote add origin "$work/tagorigin.git"
gitq push -q origin main
gitq tag "v${rel_version}"
tag_stage() { # <tag> <ref>
  (cd "$repo" && env TAG="$1" GITHUB_REF="$2" RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/tag-out.txt" \
    bash "$root/tools/release/stage.sh" tag)
}
: > "$work/tag-out.txt"
tag_stage "v${rel_version}" "refs/tags/v${rel_version}" >/dev/null
grep -q '^sha=[0-9a-f]\{40\}$' "$work/tag-out.txt" && echo "ok: tag on main accepted"
stages_run+=(tag)
expect_fail "run from a branch instead of the tag" tag_stage "v${rel_version}" "refs/heads/main"
gitq switch -q -c side
gitq commit -q --allow-empty -m side
gitq tag -f "v${rel_version}" >/dev/null
expect_fail "tag not on main" tag_stage "v${rel_version}" "refs/tags/v${rel_version}"
grep -q 'is not on main' "$work/neg.log" && echo "ok: message says the tag is not on main"
rm -rf "$repo" "$work/tagorigin.git"

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

# Everything below runs exactly as release.yml does: RUNNER_TEMP is the scratch
# root and the commands are the stage.sh stages.
export RUNNER_TEMP="$work"
export TAG="$tag"
export APKSIGNER="$apksigner"

# Never leave signing material behind, even when a step fails.
trap 'bash tools/release/stage.sh cleanup >/dev/null' EXIT

echo "== stage prepare"
run_stage prepare
stat -c '%a %n' "$work/signing/release.jks" "${apps[0]}/key.properties" "${apps[1]}/key.properties"

echo "== stage build"
run_stage build

# Pinned digest: the certificate digest of the throwaway key, read from an APK.
first="$(ls "$work"/release/*.apk | head -n1)"
real="$("$apksigner" verify --print-certs "$first" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
printf '%s' "$real" | grep -Eq '^[0-9a-f]{64}$' || { echo "FAIL: cannot read the digest"; exit 1; }
wrong="$(printf '%s' "$real" | tr '0-9a-f' '1-9a-f0')"

echo "== verify_signature negative tests (wrong pinned digest, v1-only signature)"
expect_fail "wrong pinned certificate digest" env EXPECTED_CERT_SHA256="$wrong" \
  bash tools/release/verify_signature.sh "$work/neg.txt" -- "$first"
expect_fail "malformed pinned certificate digest" env EXPECTED_CERT_SHA256="not-a-digest" \
  bash tools/release/verify_signature.sh "$work/neg.txt" -- "$first"
# A copy of the real APK re-signed with the v1 (JAR) scheme only.
v1="$work/v1only.p12"
keytool -genkeypair -keystore "$v1" -storetype PKCS12 -alias k -keyalg RSA -keysize 2048 \
  -validity 2 -dname "CN=Consolarr dry run v1" -storepass changeit -keypass changeit 2>/dev/null
cp "$first" "$work/v1only.apk"
"$apksigner" sign --ks "$v1" --ks-pass pass:changeit --key-pass pass:changeit \
  --min-sdk-version 23 --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
  "$work/v1only.apk"
rm -f "$v1"
expect_fail "APK without the v2 and v3 signature schemes" \
  bash tools/release/verify_signature.sh "$work/neg.txt" -- "$work/v1only.apk"
rm -f "$work/v1only.apk"
echo "== verify_signature: an empty pinned digest only warns"
EXPECTED_CERT_SHA256="" bash tools/release/verify_signature.sh "$work/neg.txt" -- "$first" >"$work/warn.log"
grep -q '^::warning::' "$work/warn.log" && echo "ok: warning emitted, verification continued"

echo "== stage verify (the pinned digest, in upper case with colons, must be accepted)"
pinned="$(printf '%s' "$real" | tr 'a-f' 'A-F' | sed 's/../&:/g; s/:$//')"
export GITHUB_OUTPUT="$work/gh-output.txt" GITHUB_STEP_SUMMARY="$work/gh-summary.md"
: > "$GITHUB_OUTPUT"
EXPECTED_CERT_SHA256="$pinned" run_stage verify
grep -q '^sums_sha256=[0-9a-f]\{64\}$' "$GITHUB_OUTPUT" && grep -q '^cert_sha256=[0-9a-f]\{64\}$' "$GITHUB_OUTPUT"
(cd "$work/release" && sha256sum -c SHA256SUMS.txt)

echo "== stage cleanup (right after verify, as in release.yml)"
run_stage cleanup
for f in "$work/signing/release.jks" "${apps[0]}/key.properties" "${apps[1]}/key.properties"; do
  [ ! -e "$f" ] || { echo "FAIL: ${f} still exists"; exit 1; }
done

echo "== verify_signature rejects a different certificate and a debug certificate"
other="$work/other.p12"
for dn in "CN=Someone Else" "CN=Android Debug,O=Android,C=US"; do
  keytool -genkeypair -keystore "$other" -storetype PKCS12 -alias k -keyalg RSA -keysize 2048 \
    -validity 2 -dname "$dn" -storepass changeit -keypass changeit 2>/dev/null
  cp "$first" "$work/resigned.apk"
  "$apksigner" sign --ks "$other" --ks-pass pass:changeit --key-pass pass:changeit "$work/resigned.apk"
  rm -f "$other"
  if [ "$dn" = "CN=Someone Else" ]; then
    expect_fail "mixed signing certificates" \
      bash tools/release/verify_signature.sh "$work/neg.txt" -- "$work/resigned.apk" "$work"/release/*.apk
  else
    expect_fail "Android debug certificate" \
      bash tools/release/verify_signature.sh "$work/neg.txt" -- "$work/resigned.apk"
  fi
done
rm -f "$work/resigned.apk"

echo "== no debug-info in the release files"
if ls "$work/release" | grep -qiE 'symbols|debug-info'; then echo "FAIL: symbols staged"; exit 1; fi
ls "$work/debug-info"

echo "== stage publish (with a fake gh): checks, then the draft release"
fake="$work/fakebin"
mkdir -p "$fake" "$work/pub"
cat > "$fake/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh: records calls; FAKE_TAG_SHA is what the tag "points at" now.
echo "gh $*" >> "$FAKE_GH_LOG"
case "$1 $2" in
  "release view") exit 1 ;;
  "release create") exit 0 ;;
  "api --paginate") echo "refs/tags/v0.0.1" ;;
  "api repos/"*) echo "$FAKE_TAG_SHA" ;;
  *) exit 0 ;;
esac
GH
chmod +x "$fake/gh"
rm -rf "$work/pub/release"
cp -r "$work/release" "$work/pub/release"
verified_sha="$(printf 'a%.0s' $(seq 1 40))"
moved_sha="$(printf 'b%.0s' $(seq 1 40))"
sums="$(grep '^sums_sha256=' "$GITHUB_OUTPUT" | cut -d= -f2)"
cert="$(grep '^cert_sha256=' "$GITHUB_OUTPUT" | cut -d= -f2)"
pub_env=(PATH="$fake:$PATH" FAKE_GH_LOG="$work/gh.log" GH_REPO=example/example
  SHA="$verified_sha" RECORDED_SUMS_SHA256="$sums" RECORDED_CERT_SHA256="$cert")
root="$(pwd)"

: > "$work/gh.log"
expect_fail "tag moved after verification" env "${pub_env[@]}" FAKE_TAG_SHA="$moved_sha" \
  bash -c 'cd "$1/pub" && bash "$2/tools/release/stage.sh" publish' _ "$work" "$root"
grep -q 'Tag moved after verification' "$work/neg.log" && echo "ok: message says the tag moved"
if grep -q 'release create' "$work/gh.log"; then echo "FAIL: release created although the tag moved"; exit 1; fi

expect_fail "SHA256SUMS.txt changed between jobs" env "${pub_env[@]}" FAKE_TAG_SHA="$verified_sha" \
  RECORDED_SUMS_SHA256="$wrong$wrong" bash -c 'cd "$1/pub" && bash "$2/tools/release/stage.sh" publish' _ "$work" "$root"
expect_fail "certificate digest changed between jobs" env "${pub_env[@]}" FAKE_TAG_SHA="$verified_sha" \
  RECORDED_CERT_SHA256="$wrong" bash -c 'cd "$1/pub" && bash "$2/tools/release/stage.sh" publish' _ "$work" "$root"
first_pub="$(ls "$work"/pub/release/*.apk | head -n1)"
printf 'x' >> "$first_pub"
expect_fail "an APK changed between jobs" env "${pub_env[@]}" FAKE_TAG_SHA="$verified_sha" \
  bash -c 'cd "$1/pub" && bash "$2/tools/release/stage.sh" publish' _ "$work" "$root"
cp "$first" "$first_pub"
env "${pub_env[@]}" FAKE_TAG_SHA="$verified_sha" \
  bash -c 'cd "$1/pub" && cd . && bash "$2/tools/release/stage.sh" publish' _ "$work" "$root" >/dev/null
grep -q 'release create v0.0.0 --draft --verify-tag' "$work/gh.log" || { echo "FAIL: no draft release call"; exit 1; }
echo "ok: draft release created when the tag and files match"
stages_run+=(publish)

echo "== the dry run ran every stage release.yml calls"
ran="$(printf '%s\n' "${stages_run[@]}" | sort -u | tr '\n' ' ')"
[ "$ran" = "$workflow_stages" ] || {
  echo "FAIL: release.yml stages (${workflow_stages}) differ from the stages run here (${ran})"
  exit 1
}
echo "ok: same stages (${ran})"
echo "Dry run complete. Certificate SHA-256: $(cat "$work/release/SIGNING-CERT-SHA256.txt")"
